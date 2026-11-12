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

  // --- Vitruvian Speaker ---------------------------------------------------------

  /**
   * The one word on the Vitruvian Speaker plate, worst problem first.
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
  public fun vitruvianSpeakerStatus(
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

  /** Shown when the helper or Vitruvian Speaker is too old to supply the `settings[]` catalog. */
  public const val UPDATE_SPEAKER_MESSAGE: String =
      "Update Vitruvian Speaker and the Vitruvian Remote helper on your Mac to change these settings here."

  /**
   * The single point-of-view substitution on the phone: Vitruvian Speaker's `"Your phone"` becomes
   * [THIS_PHONE] (`"This phone"`).
   */
  public fun phoneWording(text: String): String = text.replace("Your phone", THIS_PHONE)

  /**
   * Relayed `outputs_label` from Vitruvian Speaker with [phoneWording] applied, or null when blank.
   */
  public fun outputsSummary(outputsLabel: String?): String? =
      outputsLabel?.trim()?.takeIf { it.isNotEmpty() }?.let(::phoneWording)

  /** True only when Vitruvian Speaker is available and sent a non-empty `settings[]` catalog. */
  public fun hasVitruvianSpeakerCatalog(
      available: Boolean,
      catalog: VitruvianSpeakerCatalog
  ): Boolean = available && !catalog.isEmpty

  /**
   * The single sentence shown when `settings[]` is missing: the helper's own [reason] when present,
   * else [UPDATE_SPEAKER_MESSAGE].
   */
  public fun missingCatalogMessage(reason: String?): String =
      reason?.trim()?.takeIf { it.isNotEmpty() } ?: UPDATE_SPEAKER_MESSAGE

  /** Display label for catalog setting [key], with `"Your phone"` substituted as [THIS_PHONE]. */
  public fun catalogLabel(catalog: VitruvianSpeakerCatalog, key: String): String =
      catalog[key]?.label?.let(::phoneWording).orEmpty()

  /** Visibility flag for catalog setting [key] directly from Vitruvian Speaker's `shown` field. */
  public fun catalogShown(catalog: VitruvianSpeakerCatalog, key: String): Boolean =
      catalog[key]?.shown == true

  /** Selectable choices for catalog setting [key], with [phoneWording] applied to labels. */
  public fun catalogChoices(
      catalog: VitruvianSpeakerCatalog,
      key: String
  ): List<VitruvianSpeakerChoice> =
      catalog[key]?.choices.orEmpty().map { it.copy(label = phoneWording(it.label)) }

  /** Display label for [value] in catalog setting [key]'s choices, or [value] if unlisted. */
  public fun catalogChoiceLabel(
      catalog: VitruvianSpeakerCatalog,
      key: String,
      value: String
  ): String = catalogChoices(catalog, key).firstOrNull { it.value == value }?.label ?: value

  /** Numeric limits (`min`, `max`, `step`, `defaultValue`) for catalog setting [key]. */
  public fun catalogLimits(catalog: VitruvianSpeakerCatalog, key: String): VitruvianSpeakerLimits? =
      catalog[key]?.limits

  /** Pure stepper button specification derived from a catalog entry's [VitruvianSpeakerLimits]. */
  public data class StepperSpec(
      val minusLabel: String,
      val minusEnabled: Boolean,
      val minusNext: Double,
      val plusLabel: String,
      val plusEnabled: Boolean,
      val plusNext: Double,
  )

  /**
   * Builds − / + stepper buttons from [limits]. The next value stops at Vitruvian Speaker's own min
   * and max, so the phone never sends one outside them.
   */
  public fun catalogStepper(
      current: Double,
      limits: VitruvianSpeakerLimits,
      canAct: Boolean,
      unitSuffix: String = "",
  ): StepperSpec {
    val stepText =
        if (limits.step % 1.0 == 0.0) limits.step.toLong().toString() else decimal(limits.step)
    return StepperSpec(
        minusLabel = "−$stepText$unitSuffix",
        minusEnabled = canAct && current > limits.min,
        minusNext = maxOf(limits.min, current - limits.step),
        plusLabel = "+$stepText$unitSuffix",
        plusEnabled = canAct && current < limits.max,
        plusNext = minOf(limits.max, current + limits.step),
    )
  }

  /**
   * The speaker's live volume is the device's 0-100 range, not a Vitruvian Speaker setting, so the
   * phone keeps it inside that range before sending.
   */
  public fun clampSpeakerVolume(percent: Int): Int = percent.coerceIn(0, 100)

  /** The inline error recorded under catalog [key], or null. Rows look their error up by key. */
  public fun settingError(errors: Map<String, String>, key: String): String? = errors[key]

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

  /** Sub-line for the Quiet hours top metric card on the Vitruvian Speaker dashboard. */
  public fun quietHoursMetricSub(
      enabled: Boolean,
      active: Boolean,
      start: String,
  ): String =
      when {
        !enabled -> "always speaks"
        active -> "quiet now"
        start.isBlank() -> "quiet hours on"
        else -> "quiet from $start"
      }

  /** Coding agents Vitruvian Speaker installs a hook for (Swift `CodingAgent.supportsHook`). */
  public val hookAgentSlugs: Set<String> = setOf("claude-code", "antigravity", "opencode")

  /**
   * True when the active Vitruvian Speaker owner process is running on the Mac and at least one
   * chat source is enabled (`Pages.swift` `chat.ownerRunning && anySourceEnabled`). When an older
   * helper omits `owner_running` (`null`), keeps the Start/Stop toggle visible as before for
   * backward compatibility; hides it when `owner_running` is explicitly `false`.
   */
  public fun showsChatMonitorControl(
      ownerRunning: Boolean?,
      anySourceEnabled: Boolean,
  ): Boolean =
      when (ownerRunning) {
        false -> false
        null -> true
        true -> anySourceEnabled
      }

  /** Subtitle for the Chat monitor row, surfacing the last poll relative time when running. */
  public fun chatMonitorSubtitle(
      running: Boolean,
      lastPollRelative: String = "",
      ownerRunning: Boolean? = null,
      anySourceEnabled: Boolean = true,
  ): String =
      when {
        running && lastPollRelative.isNotBlank() ->
            "Monitoring chat apps · last checked $lastPollRelative"
        running -> "Monitoring chat apps in background"
        ownerRunning == false && anySourceEnabled ->
            "Stopped · open Vitruvian Speaker on the Mac to start"
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

  /** Pure specification for a row in the Vitruvian Speaker "Google Cloud OAuth" section. */
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
      activeBackendLabel: String,
      monitorRunning: Boolean,
  ): String {
    // The backend is named the way Vitruvian Speaker's own catalog names it.
    val via = activeBackendLabel.trim()
    return if (monitorRunning && via.isNotEmpty()) {
      "currently reading via $via"
    } else {
      "which backend reads Google Chat"
    }
  }

  /** Shown under Google Home or Google Chat account after starting OAuth on the Mac. */
  public const val FINISH_SIGN_IN_ON_MAC: String = "Finish signing in on your Mac"

  /** How long [FINISH_SIGN_IN_ON_MAC] stays pending before timing out (5 minutes). */
  public const val SIGN_IN_TIMEOUT_MS: Long = 5 * 60 * 1000L

  /** Inline note shown when a Mac sign-in does not finish within [SIGN_IN_TIMEOUT_MS]. */
  public const val SIGN_IN_TIMED_OUT_NOTE: String = "Sign-in didn't finish on the Mac. Try again."

  /**
   * Returned by the Mac agent (HTTP 409) when a second sign-in/grant/disconnect overlaps one in
   * flight.
   */
  public const val SIGN_IN_ALREADY_RUNNING: String =
      "A Vitruvian Speaker sign-in is already running on the Mac"

  /**
   * Pure result of evaluating a pending Mac sign-in or Chat grant against the latest poll and
   * clock.
   */
  public data class PendingSignInState(
      val pending: Boolean,
      val timedOut: Boolean,
      val pendingSinceMs: Long?,
      val inlineNote: String?,
  )

  /**
   * Resolves a pending Mac sign-in (or Chat grant) given [pendingSinceMs], whether the latest poll
   * reports [signedIn], and the current timestamp [nowMs].
   * - If [signedIn] is true, the pending state clears (`pending = false`, `pendingSinceMs = null`,
   *   `inlineNote = null`).
   * - If [pendingSinceMs] is non-null and at least [SIGN_IN_TIMEOUT_MS] (5 minutes) has elapsed at
   *   [nowMs], the pending state times out (`pending = false`, `timedOut = true`, `pendingSinceMs =
   *   null`, `inlineNote = SIGN_IN_TIMED_OUT_NOTE`).
   * - If [pendingSinceMs] is non-null and less than [SIGN_IN_TIMEOUT_MS] has elapsed, it stays
   *   pending (`pending = true`, `timedOut = false`, `pendingSinceMs = pendingSinceMs`, `inlineNote
   *   = null`).
   */
  public fun resolvePendingSignIn(
      pendingSinceMs: Long?,
      signedIn: Boolean,
      nowMs: Long,
  ): PendingSignInState {
    if (signedIn || pendingSinceMs == null) {
      return PendingSignInState(
          pending = false,
          timedOut = false,
          pendingSinceMs = null,
          inlineNote = null,
      )
    }
    if (nowMs - pendingSinceMs >= SIGN_IN_TIMEOUT_MS) {
      return PendingSignInState(
          pending = false,
          timedOut = true,
          pendingSinceMs = null,
          inlineNote = SIGN_IN_TIMED_OUT_NOTE,
      )
    }
    return PendingSignInState(
        pending = true,
        timedOut = false,
        pendingSinceMs = pendingSinceMs,
        inlineNote = null,
    )
  }

  /** Pure poll transition for Google Home sign-in and Google Chat grant pending states. */
  public data class PollPendingSignInUpdate(
      val signIn: PendingSignInState,
      val chatGrant: PendingSignInState,
  )

  /**
   * Pure poll transition used when a `/v1/speaker` poll arrives: clears pending sign-in when
   * [signedIn] is true, clears pending Chat grant when [hasChatAccess] or [hasGoogleChatToken] is
   * true, and expires either after [SIGN_IN_TIMEOUT_MS] at [nowMs].
   */
  public fun updatePendingSignInOnPoll(
      signInPendingSinceMs: Long?,
      chatGrantPendingSinceMs: Long?,
      signedIn: Boolean,
      hasChatAccess: Boolean,
      hasGoogleChatToken: Boolean = false,
      nowMs: Long = 0L,
  ): PollPendingSignInUpdate =
      PollPendingSignInUpdate(
          signIn = resolvePendingSignIn(signInPendingSinceMs, signedIn = signedIn, nowMs = nowMs),
          chatGrant =
              resolvePendingSignIn(
                  chatGrantPendingSinceMs,
                  signedIn = hasChatAccess || hasGoogleChatToken,
                  nowMs = nowMs,
              ),
      )

  /** Google Cloud Console URL opened by `VitruvianSpeakerTool` (`Block.openGoogleCloud`). */
  public const val GOOGLE_CLOUD_CONSOLE_URL: String =
      "https://console.cloud.google.com/apis/credentials"

  /** Pure specification for the "Google Home account" row (`Block.signIn` / `Block.signOut`). */
  public data class GoogleHomeAccountRowSpec(
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
      val showSignIn: Boolean,
      val signInEnabled: Boolean,
      val showImportLogin: Boolean,
      val importLoginEnabled: Boolean,
      val showSignOut: Boolean,
      val signOutEnabled: Boolean,
      val inlineNote: String? = null,
  )

  /**
   * Derives the "Google Home account" row state. When not signed in, offers "Sign in on Mac"
   * (`VitruvianSpeaker --sign-in`) and, if Antigravity tokens exist, "Import login". After tapping
   * "Sign in on Mac", [signInPending] (or [signInPendingSinceMs] before [SIGN_IN_TIMEOUT_MS]) shows
   * [FINISH_SIGN_IN_ON_MAC] until the next poll reports [signedIn] or 5 minutes elapse.
   */
  public fun googleHomeAccountRow(
      signedIn: Boolean,
      accountEmail: String,
      hasAntigravityTokens: Boolean,
      signInPending: Boolean = false,
      canAct: Boolean = true,
      installed: Boolean = true,
      signInPendingSinceMs: Long? = null,
      nowMs: Long = 0L,
  ): GoogleHomeAccountRowSpec {
    val email = accountEmail.trim()
    if (signedIn) {
      return GoogleHomeAccountRowSpec(
          subtitle = email.ifEmpty { "signed in" },
          trailing = "signed in",
          healthy = true,
          showSignIn = false,
          signInEnabled = false,
          showImportLogin = false,
          importLoginEnabled = false,
          showSignOut = true,
          signOutEnabled = canAct,
          inlineNote = null,
      )
    }
    val pendingState =
        if (signInPendingSinceMs != null) {
          resolvePendingSignIn(signInPendingSinceMs, signedIn = false, nowMs = nowMs)
        } else {
          PendingSignInState(
              pending = signInPending,
              timedOut = false,
              pendingSinceMs = null,
              inlineNote = null,
          )
        }
    val sub =
        when {
          pendingState.pending -> FINISH_SIGN_IN_ON_MAC
          email.isNotEmpty() -> email
          else -> "not signed in"
        }
    return GoogleHomeAccountRowSpec(
        subtitle = sub,
        trailing = if (pendingState.pending) "signing in…" else "sign in",
        healthy = false,
        showSignIn = true,
        signInEnabled = canAct && installed,
        showImportLogin = hasAntigravityTokens,
        importLoginEnabled = canAct,
        showSignOut = false,
        signOutEnabled = false,
        inlineNote = pendingState.inlineNote,
    )
  }

  /** Signed-in Google Chat account and backend readiness diagnostic. */
  public data class GoogleChatAccountDiag(
      val account: String,
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
      val showGrant: Boolean = false,
      val grantEnabled: Boolean = false,
      val showDisconnect: Boolean = false,
      val disconnectEnabled: Boolean = false,
      val showGwsPrompt: Boolean = false,
      val gwsPromptEnabled: Boolean = false,
      val inlineNote: String? = null,
  )

  /**
   * Derives the Google Chat account and access status row from the fields reported by
   * `/v1/speaker`, including the "Grant…" (`Block.grantChat`) and "Disconnect"
   * (`Block.disconnectChat`) actions matching `Pages.swift`.
   */
  public fun googleChatAccountDiag(
      source: String,
      activeBackend: String,
      accountEmail: String,
      gwsAccount: String,
      hasChatAccess: Boolean,
      gwsInstalled: Boolean,
      grantPending: Boolean = false,
      canAct: Boolean = true,
      installed: Boolean = true,
      grantPendingSinceMs: Long? = null,
      nowMs: Long = 0L,
  ): GoogleChatAccountDiag {
    val normalizedSource = source.trim().lowercase(Locale.ROOT)
    val effectiveSource =
        activeBackend.trim().lowercase(Locale.ROOT).takeIf { it == "api" || it == "gws" }
            ?: normalizedSource
    val apiEmail = accountEmail.trim()
    val cliEmail = gwsAccount.trim()
    val email =
        when (effectiveSource) {
          "gws" -> cliEmail.ifEmpty { apiEmail }
          "api" -> apiEmail.ifEmpty { cliEmail }
          else -> apiEmail.ifEmpty { cliEmail }
        }
    val offersApiActions = normalizedSource != "gws"
    val showGrant = offersApiActions && !hasChatAccess
    val grantEnabled = showGrant && canAct && installed
    val showDisconnect = offersApiActions && hasChatAccess
    val disconnectEnabled = showDisconnect && canAct && installed
    val showGwsPrompt = normalizedSource != "api"
    val gwsPromptEnabled = showGwsPrompt && canAct
    val base =
        when (effectiveSource) {
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
    val pendingState =
        if (grantPendingSinceMs != null) {
          resolvePendingSignIn(grantPendingSinceMs, signedIn = hasChatAccess, nowMs = nowMs)
        } else {
          PendingSignInState(
              pending = grantPending && !hasChatAccess,
              timedOut = false,
              pendingSinceMs = null,
              inlineNote = null,
          )
        }
    val sub = if (pendingState.pending) FINISH_SIGN_IN_ON_MAC else base.subtitle
    val trail = if (pendingState.pending) "signing in…" else base.trailing
    return base.copy(
        subtitle = sub,
        trailing = trail,
        showGrant = showGrant,
        grantEnabled = grantEnabled,
        showDisconnect = showDisconnect,
        disconnectEnabled = disconnectEnabled,
        showGwsPrompt = showGwsPrompt,
        gwsPromptEnabled = gwsPromptEnabled,
        inlineNote = pendingState.inlineNote,
    )
  }

  /** Pure specification for the Google Cloud OAuth section (`Block.openGoogleCloud`). */
  public data class GoogleCloudOAuthRowSpec(
      val setupTitle: String,
      val setupSubtitle: String,
      val setupActionLabel: String,
      val setupUrl: String,
      val clientIdSubtitle: String,
      val clientIdTrailing: String,
      val clientIdHealthy: Boolean,
      val clientSecretSubtitle: String,
      val clientSecretTrailing: String,
      val clientSecretHealthy: Boolean,
      val promptsEnabled: Boolean,
  )

  public fun googleCloudOAuthSpec(
      customClientId: String,
      hasCustomSecret: Boolean,
      canAct: Boolean = true,
  ): GoogleCloudOAuthRowSpec {
    val id = customClientId.trim()
    return GoogleCloudOAuthRowSpec(
        setupTitle = "Set up in Google Cloud",
        setupSubtitle = "opens Google Cloud Console credentials page in browser",
        setupActionLabel = "Set up…",
        setupUrl = GOOGLE_CLOUD_CONSOLE_URL,
        clientIdSubtitle = id.ifEmpty { "Tap to paste Google Cloud OAuth client ID" },
        clientIdTrailing = if (id.isNotEmpty()) "configured" else "none",
        clientIdHealthy = id.isNotEmpty(),
        clientSecretSubtitle =
            if (hasCustomSecret) "Client secret saved on Mac" else "Tap to paste client secret",
        clientSecretTrailing = if (hasCustomSecret) "saved" else "missing",
        clientSecretHealthy = hasCustomSecret,
        promptsEnabled = canAct,
    )
  }

  /**
   * Pure specification for the "Courier token" row (`Block.saveCourierToken` /
   * `Block.clearCourierToken`).
   */
  public data class CourierTokenRowSpec(
      val title: String,
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
      val promptTitle: String,
      val placeholder: String,
      val submitLabel: String,
      val clearLabel: String?,
      val promptEnabled: Boolean,
  )

  public fun courierTokenRow(
      hasToken: Boolean,
      canAct: Boolean = true,
  ): CourierTokenRowSpec =
      CourierTokenRowSpec(
          title = "Courier token",
          subtitle = if (hasToken) "Token saved on Mac" else "Tap to paste Courier access token",
          trailing = if (hasToken) "saved" else "missing",
          healthy = hasToken,
          promptTitle = "Courier Token",
          placeholder = "Paste access token",
          submitLabel = "Save Token",
          clearLabel = if (hasToken) "Clear Token" else null,
          promptEnabled = canAct,
      )

  /**
   * Pure specification for the "Legacy chat-monitor launch agent" row (`Block.removeLegacyAgent`).
   */
  public data class LegacyLaunchAgentRowSpec(
      val title: String,
      val subtitle: String,
      val trailing: String,
      val actionLabel: String,
      val actionEnabled: Boolean,
  )

  public fun legacyLaunchAgentRow(
      canAct: Boolean = true,
      busy: Boolean = false,
  ): LegacyLaunchAgentRowSpec =
      LegacyLaunchAgentRowSpec(
          title = "Legacy chat-monitor launch agent",
          subtitle = "Installed by Vitruvian Speaker 1.x. Chat monitoring now runs inside the app.",
          trailing = "legacy",
          actionLabel = "Remove",
          actionEnabled = canAct && !busy,
      )

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

  /** What a chat-app network's switch does on the phone. */
  public enum class NetworkSwitch {
    /** On reads it, off mutes it. */
    Mute,

    /**
     * Courier only: a network Vitruvian Speaker's own Slack or Google Chat reader covers. On reads
     * it through Courier as well (`courier_read_anyway`); off leaves it to that reader.
     */
    ReadAnyway,

    /** No switch: Beeper's networks that Vitruvian Speaker reads itself. */
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
   * [network] of chat app [app] ("Beeper" or "Courier") as Vitruvian Speaker's Settings shows it. A
   * network Vitruvian Speaker reads itself is greyed for Beeper; for Courier its switch reads it
   * through Courier as well, since Courier cannot say which Slack workspace an account is.
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
            "read directly by Vitruvian Speaker · on reads it through Courier too",
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
   * Under an app's networks before the running monitor has listed them, in Vitruvian Speaker's
   * words. Null when it has, or when an older agent cannot say ([listed] null).
   */
  public fun networksLaterLine(app: String, listed: Boolean?): String? =
      if (listed == false) "Other networks show here once $app is being read." else null

  /**
   * Where Courier's token comes from. The phone never carries it: it is pasted into Vitruvian
   * Speaker on the Mac, where Courier runs.
   */
  public val courierTokenSteps: String =
      "In Courier: Settings › Integrations › New connection…, then paste the token into Vitruvian Speaker on your Mac"

  /** Courier stays off until a token is saved, as in Vitruvian Speaker's own Settings. */
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

  /** Whether [vitruvianSpeakerStatus]'s word is a good one, an off one, or a problem. */
  public enum class SpeakerHealth {
    Ok,
    Off,
    Problem,
  }

  public fun vitruvianSpeakerHealth(
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

  /** Pure specification for one button in Vitruvian Speaker's top "Now" strip. */
  public data class QuickActionSpec(
      val id: String,
      val label: String,
      val secondary: String?,
      val enabled: Boolean,
      val active: Boolean,
      val contentDescription: String,
  )

  /**
   * The Mute / Unmute control in Vitruvian Speaker's Now strip.
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
          else -> "Mute speaker, volume $percent%"
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
   * The Quiet hours control in Vitruvian Speaker's Now strip.
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
    // The window is whatever the Mac reported; with none reported there is nothing to show.
    val window = if (!available || start.isBlank() || end.isBlank()) null else "$start–$end"
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
   * The Room control in Vitruvian Speaker's Now strip.
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
   * The Replay control in Vitruvian Speaker's Now strip.
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
   * Sentinel stored as the previously observed announcement id when Vitruvian Speaker is reachable
   * and has no latest announcement yet (`recent` and `last` both empty), so that the very next real
   * announcement triggers a notification.
   */
  public const val NO_ANNOUNCEMENT_ID: String = "__none__"

  /** Pure tracking state for Vitruvian Speaker announcement notification mirroring. */
  public data class MirrorState(
      val baselineId: String? = null,
      val activeNotificationId: String? = null,
      val activeNotificationText: String? = null,
  )

  /** Notification side-effect decided by pure Vitruvian Speaker mirror functions. */
  public sealed interface MirrorNotificationAction {
    public data object None : MirrorNotificationAction

    public data class Post(val id: String, val text: String) : MirrorNotificationAction

    public data class Update(val id: String, val text: String) : MirrorNotificationAction

    public data class Cancel(val id: String) : MirrorNotificationAction
  }

  /** Pure outcome of toggling the mirror setting or observing a Vitruvian Speaker poll. */
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
   * - `null` when Vitruvian Speaker is not available yet (so the first reachable poll still counts
   *   as first load and does not notify).
   * - The newest broadcast's trimmed `id` when non-blank.
   * - [NO_ANNOUNCEMENT_ID] when Vitruvian Speaker is available but has no broadcast with a
   *   non-blank id (so the very next real announcement triggers a notification).
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
   * Pure decision for whether to post a phone notification when Vitruvian Speaker state is
   * observed:
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
   *   the current Vitruvian Speaker snapshot so the already-latest announcement is never notified,
   *   and emits [MirrorNotificationAction.None].
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
   * Pure decision when a Vitruvian Speaker status snapshot is observed:
   * - Picks the newest announcement from `recent` (falling back to `last`).
   * - When Vitruvian Speaker is unavailable (`!available`), preserves `baselineId` so the first
   *   reachable poll will not notify, while still cancelling an active notification if mirroring
   *   was disabled or lost permission.
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

  /** Builds all five controls for Vitruvian Speaker's Now strip in display order. */
  public fun vitruvianSpeakerQuickActions(
      hasCatalog: Boolean = true,
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
  ): List<QuickActionSpec> {
    val replay =
        replayQuickAction(
            paired = paired,
            available = available,
            installed = installed,
            hasReplay = hasReplay,
            target = replayTarget,
        )
    // Without Vitruvian Speaker's catalog every control that changes a setting is hidden; replaying
    // speaks, it does not change a setting.
    if (!hasCatalog) return listOf(replay)
    return listOf(
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
        replay,
        snoozeQuickAction(
            paired = paired,
            available = available,
            snoozeUntil = snoozeUntil,
            nowMs = nowMs,
            zoneId = zoneId,
        ),
    )
  }

  private val HTTP_CODE_REGEX = Regex("""\bHTTP\s+\d{3}\b""", RegexOption.IGNORE_CASE)
  private val AUTH_CODE_REGEX = Regex("""\bHTTP\s+40[13]\b""", RegexOption.IGNORE_CASE)
  private val LEAKED_PATH_OR_CODE_REGEX = Regex("""(?:/v\d+/|https?://)""", RegexOption.IGNORE_CASE)
  private val TECHNICAL_PREFIX_REGEX =
      Regex(
          """^(?:[✗✓!]\s*|(?:agent|speaker|google\s+home|google\s+chat|gws|oauth)\s*(?:·\s*[^:]+)?:\s*|(?:error|failed|failure)\s*:\s*|[a-z][a-z ]{0,40}?\s+(?:failed|error)\s*:\s*|http\s+\d{3}(?:\s+[a-z][a-z ]*)?\s*:\s*)+""",
          RegexOption.IGNORE_CASE,
      )
  private val TRAILING_HTTP_REGEX =
      Regex("""\s*\(\s*HTTP\s+\d{3}[^)]*\)\s*$""", RegexOption.IGNORE_CASE)
  private val BARE_STATUS_OR_EXIT_REGEX =
      Regex(
          """^(?:HTTP\s+\d{3}(?:\s+for\s+\S+|\s+[a-z][a-z ]*)?|exit\s+status\s+\d+)$""",
          RegexOption.IGNORE_CASE,
      )

  /**
   * Strips raw tool/agent/HTTP prefixes (e.g. `"agent: speaker: error: ..."`, `"✗ speaker · sign in
   * on Mac: ..."`, `"HTTP 400: ..."`) leaving the human-readable reason.
   */
  public fun stripVitruvianSpeakerErrorPrefixes(raw: String): String {
    var cleaned = raw.trim()
    while (true) {
      val next = TECHNICAL_PREFIX_REGEX.replaceFirst(cleaned, "").trim()
      if (next == cleaned) break
      cleaned = next
    }
    return TRAILING_HTTP_REGEX.replace(cleaned, "").trim()
  }

  private fun plainVitruvianSpeakerAction(what: String): String {
    val raw = what.trim().ifEmpty { "update speaker" }
    return when (raw.lowercase(Locale.ROOT)) {
      "sign in on mac",
      "sign in",
      "import antigravity",
      "import antigravity login",
      "import login",
      "grant google chat",
      "grant" -> "sign in"
      "sign out" -> "sign out"
      "disconnect google chat",
      "disconnect" -> "disconnect"
      else -> raw
    }
  }

  /**
   * One-line inline error shown directly under a Vitruvian Speaker Now strip control, stream plate,
   * or Settings row when an action fails. Uses plain words rather than exception class names,
   * paths, or raw HTTP codes.
   */
  public fun vitruvianSpeakerInlineError(
      what: String,
      reason: String? = null,
      authFailed: Boolean = false,
  ): String {
    val action = plainVitruvianSpeakerAction(what)
    val raw = reason?.trim().orEmpty()
    val stripped = stripVitruvianSpeakerErrorPrefixes(raw)
    val lower = stripped.lowercase(Locale.ROOT)
    val rawLower = raw.lowercase(Locale.ROOT)
    if (authFailed ||
        AUTH_CODE_REGEX.containsMatchIn(raw) ||
        rawLower.contains("not paired") ||
        rawLower.contains("unauthorized") ||
        rawLower.contains("forbidden")) {
      return "Couldn't $action: this phone isn't paired"
    }
    // Network failures only, by the phrases Java and OkHttp use for them. Vitruvian Speaker's own
    // refusals reach the phone verbatim and may say "refused" or "reset"; those must keep
    // their words, so no bare "refused" / "reset" / "connect" here.
    val unreachable =
        raw.isEmpty() ||
            lower.contains("timeout") ||
            lower.contains("timed out") ||
            lower.contains("connection refused") ||
            lower.contains("connection reset") ||
            lower.contains("connection closed") ||
            lower.contains("connection abort") ||
            lower.contains("econnrefused") ||
            lower.contains("econnreset") ||
            lower.contains("failed to connect") ||
            lower.contains("connectexception") ||
            lower.contains("socketexception") ||
            lower.contains("unreachable") ||
            lower.contains("eof") ||
            lower.contains("broken pipe") ||
            lower.contains("unable to resolve") ||
            lower.contains("unknownhost") ||
            lower.contains("unknown host") ||
            lower.contains("no route")
    if (unreachable) {
      return "Couldn't $action: the Mac didn't answer"
    }
    if (stripped.equals(SIGN_IN_ALREADY_RUNNING, ignoreCase = true)) {
      return SIGN_IN_ALREADY_RUNNING
    }
    if (stripped.isEmpty() ||
        BARE_STATUS_OR_EXIT_REGEX.matches(stripped) ||
        HTTP_CODE_REGEX.containsMatchIn(stripped) ||
        LEAKED_PATH_OR_CODE_REGEX.containsMatchIn(stripped) ||
        stripped.contains('/')) {
      return "Couldn't $action: the Mac returned an error"
    }
    return "Couldn't $action: $stripped"
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
   * Maps pairing and `/v1/speaker/volume` state to the Quick Settings "Speaker" tile.
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
    VitruvianSpeaker,
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
        "speaker" -> setOf(PollSource.VitruvianSpeaker, PollSource.SpeakerVolume)
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
          PollSource.VitruvianSpeaker,
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

  /**
   * Stream/notice wording when a module has no live response from the Mac.
   *
   * When a Mac is paired (`[paired] == true`) and unreachable (`[offline] == true`), names the host
   * and appends `"last seen <relative time>"` (or omits `"last seen"` when `[lastSeenAgoSec] ==
   * null`). Keeps `"no Mac is configured, so nothing ran/was asked"` only for the truly-unpaired
   * case (`[paired] == false`).
   */
  public fun noMacLine(
      paired: Boolean,
      offline: Boolean,
      hostName: String,
      lastSeenAgoSec: Long?,
      nothingRan: Boolean = false,
  ): String {
    if (paired) {
      if (!offline) return "asking…"
      val name = hostName.trim().ifEmpty { "the Mac" }
      val rel =
          if (lastSeenAgoSec != null && lastSeenAgoSec >= 0L) {
            Format.relativeSeconds(lastSeenAgoSec)
          } else {
            ""
          }
      return if (rel.isNotEmpty()) "$name isn't answering · last seen $rel"
      else "$name isn't answering"
    }
    return if (nothingRan) "no Mac is configured, so nothing ran"
    else "no Mac is configured, so nothing was asked"
  }

  /**
   * Chooses the display name for a Mac host:
   * - A user-typed [alias] (non-blank and not auto-derived by [HostCodec.aliasFor]) always wins.
   * - When [alias] equals [HostCodec.aliasFor] (or is blank) and the agent has reported
   *   [agentHostname] (`/v1/host`), returns `Format.shortHost(agentHostname)`.
   * - Otherwise returns the auto-derived alias.
   */
  public fun displayHostName(
      alias: String,
      url: String,
      agentHostname: String?,
  ): String {
    val trimmedAlias = alias.trim()
    val auto = HostCodec.aliasFor(url)
    if (trimmedAlias.isNotEmpty() && !HostCodec.isAutoAlias(trimmedAlias, url)) {
      return trimmedAlias
    }
    val shortHost = agentHostname?.let(Format::shortHost)?.takeIf { it.isNotBlank() }
    if (shortHost != null) return shortHost
    return if (trimmedAlias.isNotEmpty() && trimmedAlias == auto) trimmedAlias else auto
  }

  /** Specification for the "Show announcements as notifications" row on the phone. */
  public data class MirrorRowSpec(
      val checked: Boolean,
      val trailing: String,
      val error: String?,
      val showOpenSettings: Boolean,
      val actionLabel: String = "Open settings",
  )

  /**
   * True when the user denied notification permission and Android will not prompt again (`[asked]
   * == true` and `[shouldShowRationale] == false`). Before the app has ever asked (`[asked] ==
   * false`) or after a first denial (`[shouldShowRationale] == true`), Android can still prompt, so
   * it is not treated as permanently blocked.
   */
  public fun isNotificationPermissionBlocked(
      granted: Boolean,
      shouldShowRationale: Boolean,
      asked: Boolean = true,
  ): Boolean = !granted && asked && !shouldShowRationale

  /** Action offered by a contextual notification-permission row. */
  public enum class NotificationPermissionAction {
    None,
    Allow,
    OpenSettings,
  }

  /** Specification for the Settings screen's "Notifications" row. */
  public data class NotificationsRowSpec(
      val title: String,
      val subtitle: String,
      val statusLabel: String?,
      val action: NotificationPermissionAction,
      val actionLabel: String?,
      val permanentlyBlocked: Boolean,
  )

  /**
   * Pure decision logic for the Settings screen's "Notifications" row across all four permission
   * states: granted, not asked, denied once, and permanently blocked.
   */
  public fun notificationsRowSpec(
      granted: Boolean,
      asked: Boolean,
      shouldShowRationale: Boolean,
  ): NotificationsRowSpec {
    val title = "Notifications"
    val subtitle = "Mac offline/back alerts and finished commands"
    if (granted) {
      return NotificationsRowSpec(
          title = title,
          subtitle = subtitle,
          statusLabel = "On",
          action = NotificationPermissionAction.None,
          actionLabel = null,
          permanentlyBlocked = false,
      )
    }
    val blocked =
        isNotificationPermissionBlocked(
            granted = false,
            shouldShowRationale = shouldShowRationale,
            asked = asked,
        )
    return if (blocked) {
      NotificationsRowSpec(
          title = title,
          subtitle = subtitle,
          statusLabel = null,
          action = NotificationPermissionAction.OpenSettings,
          actionLabel = "Open settings",
          permanentlyBlocked = true,
      )
    } else {
      NotificationsRowSpec(
          title = title,
          subtitle = subtitle,
          statusLabel = null,
          action = NotificationPermissionAction.Allow,
          actionLabel = "Allow",
          permanentlyBlocked = false,
      )
    }
  }

  /** Inline note shown under Phone Bridge when enabled while notifications are off. */
  public data class BridgeNotificationSpec(
      val note: String,
      val action: NotificationPermissionAction,
      val actionLabel: String,
      val permanentlyBlocked: Boolean,
  )

  /**
   * Pure decision logic for the Phone Bridge row's notification-permission note across bridge off,
   * granted, not asked, denied once, and permanently blocked.
   */
  public fun bridgeNotificationSpec(
      bridgeEnabled: Boolean,
      granted: Boolean,
      asked: Boolean,
      shouldShowRationale: Boolean,
  ): BridgeNotificationSpec? {
    if (!bridgeEnabled || granted) return null
    val note = "Approvals can't pop up while notifications are off"
    val blocked =
        isNotificationPermissionBlocked(
            granted = false,
            shouldShowRationale = shouldShowRationale,
            asked = asked,
        )
    return if (blocked) {
      BridgeNotificationSpec(
          note = note,
          action = NotificationPermissionAction.OpenSettings,
          actionLabel = "Open settings",
          permanentlyBlocked = true,
      )
    } else {
      BridgeNotificationSpec(
          note = note,
          action = NotificationPermissionAction.Allow,
          actionLabel = "Allow",
          permanentlyBlocked = false,
      )
    }
  }

  /**
   * Pure decision logic for the Vitruvian Speaker phone notification mirror row.
   *
   * When notification permission is permanently denied/blocked (`[permissionBlocked] == true` and
   * `[shouldShowRationale] == false`), shows the toggle as off (`checked = false`), surfaces
   * `"Notifications are blocked for this app"`, and offers the `"Open settings"` row action.
   */
  public fun mirrorRowSpec(
      mirrorEnabled: Boolean,
      permissionGranted: Boolean,
      permissionBlocked: Boolean,
      shouldShowRationale: Boolean = false,
  ): MirrorRowSpec {
    if (permissionBlocked &&
        isNotificationPermissionBlocked(permissionGranted, shouldShowRationale)) {
      return MirrorRowSpec(
          checked = false,
          trailing = "off",
          error = "Notifications are blocked for this app",
          showOpenSettings = true,
      )
    }
    val on = isMirrorEnabled(mirrorEnabled, permissionGranted)
    return MirrorRowSpec(
        checked = on,
        trailing = if (on) "on" else "off",
        error = null,
        showOpenSettings = false,
    )
  }

  /** Confirmation window for two-tap "Reset Vitruvian Speaker". */
  public const val RESET_CONFIRM_WINDOW_MS: Long = 5_000L

  /** Result of tapping the "Reset Vitruvian Speaker" action. */
  public data class ResetTapResult(
      val shouldReset: Boolean,
      val nextArmedAtMs: Long?,
  )

  /** Specification for the "Reset Vitruvian Speaker" section/row. */
  public data class ResetRowSpec(
      val title: String,
      val subtitle: String,
      val actionLabel: String,
      val danger: Boolean,
      val enabled: Boolean,
      val armed: Boolean,
  )

  /** True when a reset tap at [armedAtMs] is still within [RESET_CONFIRM_WINDOW_MS] at [nowMs]. */
  public fun isResetArmed(armedAtMs: Long?, nowMs: Long): Boolean =
      armedAtMs != null && nowMs >= armedAtMs && (nowMs - armedAtMs) < RESET_CONFIRM_WINDOW_MS

  /**
   * Pure two-tap confirmation state machine for resetting Vitruvian Speaker settings.
   * - First tap (not armed, or window expired): arms reset for 5 s (`nextArmedAtMs = nowMs`).
   * - Second tap within 5 s: confirms reset (`shouldReset = true`, `nextArmedAtMs = null`).
   */
  public fun tapReset(armedAtMs: Long?, nowMs: Long): ResetTapResult =
      if (isResetArmed(armedAtMs, nowMs)) {
        ResetTapResult(shouldReset = true, nextArmedAtMs = null)
      } else {
        ResetTapResult(shouldReset = false, nextArmedAtMs = nowMs)
      }

  /** Builds the row spec for the "Reset Vitruvian Speaker" section. */
  public fun resetVitruvianSpeakerRow(
      armedAtMs: Long?,
      nowMs: Long,
      canAct: Boolean,
      busy: Boolean = false,
  ): ResetRowSpec {
    val armed = isResetArmed(armedAtMs, nowMs)
    return ResetRowSpec(
        title = "Reset Vitruvian Speaker",
        subtitle = "puts every Vitruvian Speaker setting back to default",
        actionLabel = if (armed) "Tap again to reset" else "Reset settings",
        danger = armed,
        enabled = canAct && !busy,
        armed = armed,
    )
  }

  /**
   * True when the Courier row should be shown in Chat apps.
   *
   * Hidden only when the Mac agent does not support Courier at all (`[courierEnabled] == null` on
   * an older agent that omits Courier fields). Shown when Courier is off or tokenless
   * (`[courierEnabled] == false`) or on (`[courierEnabled] == true`).
   */
  public fun showsCourierRow(courierEnabled: Boolean?): Boolean = courierEnabled != null

  /**
   * Every catalog key in [catalogKeys] that was not claimed by a hand-designed row in [drawnKeys],
   * preserving catalog order so `"Other settings"` draws every unplaced key in order and nothing is
   * dropped.
   */
  public fun genericKeys(
      catalogKeys: List<String>,
      drawnKeys: Set<String>,
  ): List<String> = catalogKeys.filter { it !in drawnKeys }

  /**
   * Per-build tracker for hand-placed catalog settings in `vitruvianSpeakerModule`. Calling
   * [placed] records `key` once and returns `null` (draws nothing) if `key` was already recorded in
   * this build; any catalog key not recorded falls through to [genericKeys] /
   * [genericVitruvianSpeakerRows].
   */
  public class CatalogPlacement {
    private val recorded = LinkedHashSet<String>()

    public val drawnKeys: Set<String>
      get() = recorded

    public fun <T> placed(key: String, build: () -> T): T? {
      if (!recorded.add(key)) return null
      return build()
    }
  }

  /** Pure control model for a row in the generic `"Other settings"` group. */
  public sealed interface GenericSettingControl {
    public data class Toggle(
        val checked: Boolean,
        val enabled: Boolean,
    ) : GenericSettingControl

    public data class Choices(
        val current: String,
        val options: List<VitruvianSpeakerChoice>,
        val enabled: Boolean,
    ) : GenericSettingControl

    public data class NumberStepper(
        val current: Double,
        val stepper: StepperSpec?,
        val options: List<VitruvianSpeakerChoice>,
        val isInteger: Boolean,
        val enabled: Boolean,
    ) : GenericSettingControl

    public data class TextPrompt(
        val value: String,
        val hasValue: Boolean,
        val enabled: Boolean,
    ) : GenericSettingControl
  }

  /** Pure row model for a catalog setting rendered by the generic `"Other settings"` section. */
  public data class GenericSettingRow(
      val key: String,
      val kind: String,
      val title: String,
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
      val shown: Boolean,
      val error: String?,
      val control: GenericSettingControl,
  )

  private fun halfHourTimeOptions(keeping: String): List<VitruvianSpeakerChoice> {
    val base =
        (0..23).flatMap { hour ->
          listOf(0, 30).map { minute ->
            val slot = String.format(Locale.ROOT, "%02d:%02d", hour, minute)
            VitruvianSpeakerChoice(value = slot, label = slot)
          }
        }
    val trimmed = keeping.trim()
    return if (trimmed.isNotEmpty() && base.none { it.value == trimmed }) {
      listOf(VitruvianSpeakerChoice(value = trimmed, label = trimmed)) + base
    } else {
      base
    }
  }

  /**
   * Maps one [VitruvianSpeakerSetting] to its pure generic row model, or `null` if `kind` is
   * unknown. Applies [phoneWording] to labels and choice labels and honors catalog `choices` and
   * `limits`.
   */
  public fun genericVitruvianSpeakerRow(
      setting: VitruvianSpeakerSetting,
      canAct: Boolean = true,
      error: String? = null,
  ): GenericSettingRow? {
    val title = phoneWording(setting.label).ifBlank { setting.key }
    return when (setting.kind) {
      "toggle" -> {
        val checked = setting.boolValue == true
        GenericSettingRow(
            key = setting.key,
            kind = setting.kind,
            title = title,
            subtitle = "",
            trailing = if (checked) "on" else "off",
            healthy = checked,
            shown = setting.shown,
            error = error,
            control = GenericSettingControl.Toggle(checked = checked, enabled = canAct),
        )
      }
      "choice" -> {
        val options = setting.choices.map { it.copy(label = phoneWording(it.label)) }
        val current = setting.stringValue
        val currentLabel =
            options.firstOrNull { it.value == current }?.label ?: phoneWording(current)
        GenericSettingRow(
            key = setting.key,
            kind = setting.kind,
            title = title,
            subtitle = "",
            trailing = currentLabel,
            healthy = false,
            shown = setting.shown,
            error = error,
            control =
                GenericSettingControl.Choices(
                    current = current,
                    options = options,
                    enabled = canAct,
                ),
        )
      }
      "time" -> {
        val current = setting.stringValue
        val rawOptions =
            if (setting.choices.isNotEmpty()) {
              val mapped = setting.choices.map { it.copy(label = phoneWording(it.label)) }
              if (current.isNotBlank() && mapped.none { it.value == current }) {
                listOf(VitruvianSpeakerChoice(current, current)) + mapped
              } else {
                mapped
              }
            } else {
              halfHourTimeOptions(current)
            }
        val currentLabel = rawOptions.firstOrNull { it.value == current }?.label ?: current
        GenericSettingRow(
            key = setting.key,
            kind = setting.kind,
            title = title,
            subtitle = "",
            trailing = currentLabel,
            healthy = false,
            shown = setting.shown,
            error = error,
            control =
                GenericSettingControl.Choices(
                    current = current,
                    options = rawOptions,
                    enabled = canAct,
                ),
        )
      }
      "number" -> {
        val current = setting.numberValue ?: setting.limits?.defaultValue ?: 0.0
        val stepper =
            setting.limits?.let { catalogStepper(current = current, limits = it, canAct = canAct) }
        val options = setting.choices.map { it.copy(label = phoneWording(it.label)) }
        val trailing =
            options.firstOrNull { it.value.toDoubleOrNull() == current }?.label ?: decimal(current)
        val isInt = (setting.limits?.step ?: 1.0) % 1.0 == 0.0 && current % 1.0 == 0.0
        GenericSettingRow(
            key = setting.key,
            kind = setting.kind,
            title = title,
            subtitle = "",
            trailing = trailing,
            healthy = false,
            shown = setting.shown,
            error = error,
            control =
                GenericSettingControl.NumberStepper(
                    current = current,
                    stepper = stepper,
                    options = options,
                    isInteger = isInt,
                    enabled = canAct,
                ),
        )
      }
      "text" -> {
        val value = setting.stringValue
        val hasValue = value.isNotEmpty()
        GenericSettingRow(
            key = setting.key,
            kind = setting.kind,
            title = title,
            subtitle = value.ifBlank { "Not set" },
            trailing = if (hasValue) "set" else "none",
            healthy = hasValue,
            shown = setting.shown,
            error = error,
            control =
                GenericSettingControl.TextPrompt(
                    value = value,
                    hasValue = hasValue,
                    enabled = canAct,
                ),
        )
      }
      else -> null
    }
  }

  /**
   * Returns generic `"Other settings"` rows for every catalog entry in [catalog] not claimed by
   * [drawnKeys] (via [genericKeys]). Returns an empty list when [genericSettingsSupported] is
   * `false` so older Mac helpers without `POST` `settings` support never show a control that would
   * fail. By default filters to `setting.shown == true`; pass `includeHidden = true` to audit full
   * catalog coverage regardless of current visibility state.
   */
  public fun genericVitruvianSpeakerRows(
      catalog: VitruvianSpeakerCatalog,
      canAct: Boolean = true,
      errors: Map<String, String> = emptyMap(),
      drawnKeys: Set<String> = emptySet(),
      includeHidden: Boolean = false,
      genericSettingsSupported: Boolean = true,
  ): List<GenericSettingRow> {
    if (!genericSettingsSupported) return emptyList()
    val byKey = catalog.settings.associateBy { it.key }
    return genericKeys(catalog.settings.map { it.key }, drawnKeys).mapNotNull { key ->
      val setting = byKey[key] ?: return@mapNotNull null
      if (!includeHidden && !setting.shown) return@mapNotNull null
      genericVitruvianSpeakerRow(
          setting = setting,
          canAct = canAct,
          error = settingError(errors, setting.key),
      )
    }
  }

  /** One selectable Google Home structure in the Home picker. */
  public data class HomeChoiceSpec(
      val id: String,
      val name: String,
      val selected: Boolean,
      val enabled: Boolean,
  )

  /** Pure specification for the Google Home picker row (`homes[]`). */
  public data class HomePickerSpec(
      val selectedId: String?,
      val trailing: String,
      val choices: List<HomeChoiceSpec>,
  )

  /**
   * Lists every home from [homes] and marks the selected one (`h.selected`, falling back to
   * [structureId] for older payloads without `selected`). Returns `null` when [homes] is empty so
   * older helpers degrade quietly.
   */
  public fun homePickerSpec(
      homes: List<AgentHome>,
      structureId: String = "",
      structureName: String = "",
      canAct: Boolean = true,
  ): HomePickerSpec? {
    if (homes.isEmpty()) return null
    val selectedHome =
        homes.firstOrNull { it.selected }
            ?: homes.firstOrNull { structureId.isNotBlank() && it.id == structureId }
    val selectedId = selectedHome?.id
    val trailing =
        selectedHome?.name?.takeIf { it.isNotBlank() }
            ?: structureName.takeIf { it.isNotBlank() }
            ?: "None"
    return HomePickerSpec(
        selectedId = selectedId,
        trailing = trailing,
        choices =
            homes.map { h ->
              val current = selectedId != null && h.id == selectedId
              HomeChoiceSpec(
                  id = h.id,
                  name = h.name.ifBlank { h.id },
                  selected = current,
                  enabled = canAct && !current,
              )
            },
    )
  }

  /** Pure specification for one discovered speaker row, each with its own Remove action. */
  public data class SpeakerRowSpec(
      val key: String,
      val name: String,
      val title: String,
      val subtitle: String,
      val trailing: String,
      val selected: Boolean,
      val removeEnabled: Boolean,
  )

  /** Builds a speaker row with a Remove action for every speaker in [targets], not only default. */
  public fun speakerRowSpecs(
      targets: List<VitruvianSpeakerTargetWire>,
      canAct: Boolean = true,
  ): List<SpeakerRowSpec> =
      targets.map { t ->
        val title = phoneWording(t.displayLine.ifBlank { t.name }.ifBlank { t.key })
        val subtitle =
            if (t.type == "Structure") "every speaker at once"
            else listOf(t.room, t.type).filter { it.isNotBlank() }.joinToString(" · ")
        SpeakerRowSpec(
            key = t.key,
            name = t.name.ifBlank { title },
            title = title,
            subtitle = subtitle,
            trailing = if (t.selected) "default" else "",
            selected = t.selected,
            removeEnabled = canAct && t.key.isNotBlank(),
        )
      }

  /** First Vitruvian Speaker release supporting `switchTo` with `copy: true`. */
  public const val MIN_DOOR_COPY_SPEAKER_VERSION: String = "1.41.0"

  /**
   * True when [vitruvianSpeakerVersion] is at least [MIN_DOOR_COPY_SPEAKER_VERSION], the version
   * where `--apply {"op":"switchTo","door":...,"copy":true}` shipped. Blank or unparseable versions
   * return `false` so older Vitruvian Speaker installations never offer a `copy` option that
   * ignores or rejects `copy`.
   */
  public fun supportsDoorCopy(vitruvianSpeakerVersion: String): Boolean {
    val clean = vitruvianSpeakerVersion.trim().removePrefix("v").substringBefore('-')
    if (clean.isEmpty()) return false
    val actual = clean.split('.').map { it.toIntOrNull() ?: return false }
    val required = MIN_DOOR_COPY_SPEAKER_VERSION.split('.').map { it.toInt() }
    val len = maxOf(actual.size, required.size)
    for (i in 0 until len) {
      val a = actual.getOrElse(i) { 0 }
      val b = required.getOrElse(i) { 0 }
      if (a != b) return a > b
    }
    return true
  }

  /** Pure choice option on the `"Vitruvian Speaker door"` row, including copy-on-switch. */
  public data class DoorSwitchOptionSpec(
      val targetDoor: String,
      val label: String,
      val copy: Boolean,
      val selected: Boolean,
      val enabled: Boolean,
  )

  /**
   * Builds the door switch choices when both doors are relevant. When switching to the other door
   * (if installed), offers both switching as-is (`copy = false`) and `"Copy settings from the
   * <current>"` (`copy = true`, matching `DoorPages.swift` / `DoorWords.copySettingsFrom`).
   */
  public fun doorSwitchOptions(
      activeDoor: String,
      appInstalled: Boolean? = null,
      extensionInstalled: Boolean,
      canAct: Boolean = true,
      copySupported: Boolean = true,
  ): List<DoorSwitchOptionSpec> {
    if (!extensionInstalled && activeDoor != "extension") return emptyList()
    val current = if (activeDoor == "extension") "extension" else "app"
    val other = if (current == "app") "extension" else "app"
    val otherInstalled = if (other == "extension") extensionInstalled else appInstalled != false
    val currentTitle = if (current == "app") "App" else "Extension"
    val otherTitle = if (other == "app") "App" else "Extension"
    val currentWord = if (current == "app") "the app" else "the extension"
    return buildList {
      add(
          DoorSwitchOptionSpec(
              targetDoor = current,
              label = currentTitle,
              copy = false,
              selected = true,
              enabled = false,
          ))
      if (otherInstalled) {
        add(
            DoorSwitchOptionSpec(
                targetDoor = other,
                label = otherTitle,
                copy = false,
                selected = false,
                enabled = canAct,
            ))
        if (copySupported) {
          add(
              DoorSwitchOptionSpec(
                  targetDoor = other,
                  label = "Copy settings from $currentWord",
                  copy = true,
                  selected = false,
                  enabled = canAct,
              ))
        }
      }
    }
  }

  /**
   * Subtitle matching `Pages.hookWithoutVitruvianSpeaker` when a stale hook's target binary is
   * gone.
   */
  public const val HOOK_WITHOUT_VITRUVIANSPEAKER: String =
      "Points at Vitruvian Speaker, which isn't installed — it can't speak"

  /**
   * True when [hookState] is `"stale"` and [staleCommand] / [hookProgram] points at a Vitruvian
   * Speaker that is no longer installed (for instance `/.Trash/`, an uninstalled `Vitruvian
   * Speaker.app`, an uninstalled Vitruvian extension, or `!installed`). Returns `false` for older
   * helpers that send neither `stale_command` nor `hook_program` while Vitruvian Speaker is
   * installed.
   */
  public fun staleHookPointsAtMissingVitruvianSpeaker(
      hookState: String,
      staleCommand: String?,
      hookProgram: String?,
      installed: Boolean = true,
      appInstalled: Boolean? = null,
      extensionInstalled: Boolean = false,
  ): Boolean {
    if (hookState != "stale") return false
    if (!installed) return true
    val target =
        hookProgram?.trim()?.takeIf { it.isNotEmpty() }
            ?: staleCommand?.trim()?.takeIf { it.isNotEmpty() }
            ?: return false
    if (target.contains("/.Trash/")) return true
    if (target.contains("dev.vitruvian.speaker")) return !extensionInstalled
    val pointsAtApp =
        target.contains("Vitruvian Speaker.app") ||
            target.endsWith("/VitruvianSpeaker") ||
            target.contains("/VitruvianSpeaker ") ||
            target.contains("/VitruvianSpeaker'") ||
            target.contains("/VitruvianSpeaker\"")
    if (pointsAtApp) return appInstalled == false
    return hookProgram.isNullOrBlank()
  }

  /** Pure specification for a coding-agent hook row in `"Coding agents"`. */
  public data class AgentHookRowSpec(
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
      val warn: Boolean,
      val showDisableRival: Boolean,
      val showInstall: Boolean,
      val showUpdate: Boolean,
      val showRemove: Boolean,
      val removeLabel: String,
      val installOrUpdateEnabled: Boolean,
      val removeOrRivalEnabled: Boolean,
  )

  /**
   * Derives a coding-agent hook row. When a stale hook points at a Vitruvian Speaker that is no
   * longer installed, offers `"Remove"` alongside `"Update hook"` (or `"Remove"` alone when no Home
   * Speaker is installed, matching `Pages.swift`).
   */
  public fun agentHookRowSpec(
      status: AgentHookStatus,
      installed: Boolean = true,
      appInstalled: Boolean? = null,
      extensionInstalled: Boolean = false,
      canAct: Boolean = true,
      busy: Boolean = false,
  ): AgentHookRowSpec {
    val isInstalled = status.hookState == "installed"
    val isStale = status.hookState == "stale"
    val missingTarget =
        staleHookPointsAtMissingVitruvianSpeaker(
            hookState = status.hookState,
            staleCommand = status.staleCommand,
            hookProgram = status.hookProgram,
            installed = installed,
            appInstalled = appInstalled,
            extensionInstalled = extensionInstalled,
        )
    val subtitle =
        if (isStale && missingTarget && !status.speaksTwice) {
          HOOK_WITHOUT_VITRUVIANSPEAKER
        } else {
          agentHookStatusLabel(status.hookState, status.speaksTwice, status.configuredByInstruction)
        }
    return AgentHookRowSpec(
        subtitle = subtitle,
        trailing = if (isInstalled) "installed" else if (isStale) "outdated" else "none",
        healthy = isInstalled && !status.speaksTwice,
        warn = status.speaksTwice || isStale,
        showDisableRival = status.speaksTwice,
        showInstall = !isInstalled && !isStale,
        showUpdate = isStale && installed,
        showRemove = isInstalled || (isStale && missingTarget),
        removeLabel = if (isInstalled) "Remove hook" else "Remove",
        installOrUpdateEnabled = canAct && !busy && installed,
        removeOrRivalEnabled = canAct && !busy,
    )
  }

  /** `0`, `6.4`, `31.6` -- `Format.decimal`'s shape; this library cannot depend on :format. */
  private fun decimal(value: Double): String {
    val rounded = Math.round(value * 10) / 10.0
    return String.format(Locale.ROOT, "%.1f", rounded).removeSuffix(".0")
  }
}

/**
 * Manifest IDs for every phone-supported Vitruvian Speaker control, matching
 * `apps/desktop/vitruvian-speaker/testdata/controls.json`.
 */
public object VitruvianSpeakerControls {
  public const val CATALOG_SETTING: String = "catalog-setting"
  public const val SAY: String = "say"
  public const val SPEAK_CLIPBOARD: String = "speak-clipboard"
  public const val SNOOZE: String = "snooze"
  public const val MUTE: String = "mute"
  public const val VOLUME: String = "volume"
  public const val SIGN_IN: String = "sign-in"
  public const val SIGN_OUT: String = "sign-out"
  public const val IMPORT_ANTIGRAVITY: String = "import-antigravity"
  public const val FIND_SPEAKERS: String = "find-speakers"
  public const val CHOOSE_HOME: String = "choose-home"
  public const val SAVE_GEMINI_KEY: String = "save-gemini-key"
  public const val CLEAR_GEMINI_KEY: String = "clear-gemini-key"
  public const val SAVE_SLACK_TOKEN: String = "save-slack-token"
  public const val CLEAR_SLACK_TOKEN: String = "clear-slack-token"
  public const val SAVE_BEEPER_TOKEN: String = "save-beeper-token"
  public const val CLEAR_BEEPER_TOKEN: String = "clear-beeper-token"
  public const val SAVE_COURIER_TOKEN: String = "save-courier-token"
  public const val CLEAR_COURIER_TOKEN: String = "clear-courier-token"
  public const val GRANT_GOOGLE_CHAT: String = "grant-google-chat"
  public const val DISCONNECT_GOOGLE_CHAT: String = "disconnect-google-chat"
  public const val BEEPER_NETWORK: String = "beeper-network"
  public const val COURIER_NETWORK: String = "courier-network"
  public const val COURIER_READ_ANYWAY: String = "courier-read-anyway"
  public const val START_CHAT_MONITOR: String = "start-chat-monitor"
  public const val STOP_CHAT_MONITOR: String = "stop-chat-monitor"
  public const val REPLAY: String = "replay"
  public const val TEST_MEDIA_PAUSE: String = "test-media-pause"
  public const val VOICE_PREVIEW: String = "voice-preview"
  public const val REMOVE_SPEAKER: String = "remove-speaker"
  public const val SET_DEFAULT_SPEAKER: String = "set-default-speaker"
  public const val HOOK_INSTALL: String = "hook-install"
  public const val HOOK_UPDATE: String = "hook-update"
  public const val HOOK_REMOVE: String = "hook-remove"
  public const val HOOK_ADD_INSTRUCTION: String = "hook-add-instruction"
  public const val HOOK_TURN_OFF_RIVAL: String = "hook-turn-off-rival"
  public const val REMOVE_LEGACY_AGENT: String = "remove-legacy-agent"
  public const val SAVE_OAUTH_CLIENT: String = "save-oauth-client"
  public const val CLEAR_OAUTH_CLIENT: String = "clear-oauth-client"
  public const val DOOR_SWITCH: String = "door-switch"
  public const val DOOR_COPY_SETTINGS: String = "door-copy-settings"
  public const val RESET: String = "reset"
}
