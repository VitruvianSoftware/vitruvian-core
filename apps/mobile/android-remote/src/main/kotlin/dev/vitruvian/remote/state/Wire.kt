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

/**
 * The three wire formats the phone parses by hand, kept away from Compose and from Android.
 *
 * Each of these fails SILENTLY when it is wrong, which is the same reason `HidCodes` and
 * `WakeOnLan` live in their own libraries: a server-sent event whose `data:` was split across two
 * reads is dropped with no error anywhere, a host list that decodes to nothing looks exactly like a
 * phone that was never paired, and a deep link that does not parse simply opens the Home screen.
 * None of the three would fail a build or raise an exception, so they get a JVM test that runs on
 * every PR instead of a device someone has to hold.
 *
 * There is no `org.json` here on purpose: it is part of the Android platform, not of the JVM, and a
 * file that imports it can only be tested on a device. The JSON reader below is the small price of
 * a test that runs in CI.
 */

// --- server-sent events -------------------------------------------------

/**
 * One event from `POST /v1/exec/stream`.
 *
 * [name] is the `event:` field ("line" or "exit"); [data] is the concatenated `data:` payload.
 */
public data class SseEvent(val name: String, val data: String)

/**
 * The SSE reader, as an incremental state machine.
 *
 * Fed raw chunks rather than whole lines because that is what a socket actually delivers: one read
 * can end halfway through `data: {"stream":"stdo`, and a parser that assumed a chunk was a line
 * would drop the rest of that command's output without a word. The trailing partial line is held
 * until the read that finishes it.
 *
 * Per the SSE grammar: a line beginning `:` is a comment (the agent's 15-second keepalive) and is
 * ignored, a blank line dispatches whatever has accumulated, and repeated `data:` lines are joined
 * with newlines. `\r\n` is accepted as well as `\n` because nothing guarantees which one arrives.
 */
public class SseParser {
  private val pending = StringBuilder()
  private var name = ""
  private val data = StringBuilder()
  private var hasData = false

  /** Feeds one chunk, calling [emit] once per completed event, in order. */
  public fun feed(chunk: String, emit: (SseEvent) -> Unit) {
    for (char in chunk) {
      if (char == '\n') {
        val line = pending.toString().removeSuffix("\r")
        pending.setLength(0)
        onLine(line, emit)
      } else {
        pending.append(char)
      }
    }
  }

  /**
   * Dispatches whatever is still buffered when the connection closes.
   *
   * An agent that exits without a trailing blank line would otherwise have its LAST event -- which
   * is always `exit`, the one carrying the exit code -- silently thrown away.
   */
  public fun close(emit: (SseEvent) -> Unit) {
    if (pending.isNotEmpty()) {
      val line = pending.toString().removeSuffix("\r")
      pending.setLength(0)
      onLine(line, emit)
    }
    dispatch(emit)
  }

  private fun onLine(line: String, emit: (SseEvent) -> Unit) {
    when {
      line.isEmpty() -> dispatch(emit)
      line.startsWith(":") -> Unit // comment: the keepalive, and nothing else
      else -> {
        val field = line.substringBefore(':')
        // "data: x" and "data:x" are the same field; exactly one leading
        // space after the colon is part of the grammar, not of the value.
        val value = line.substringAfter(':', missingDelimiterValue = "").removePrefix(" ")
        when (field) {
          "event" -> name = value
          "data" -> {
            if (hasData) data.append('\n')
            data.append(value)
            hasData = true
          }
          // id, retry and anything else this agent never sends.
          else -> Unit
        }
      }
    }
  }

  private fun dispatch(emit: (SseEvent) -> Unit) {
    if (!hasData && name.isEmpty()) return
    emit(SseEvent(name, data.toString()))
    name = ""
    data.setLength(0)
    hasData = false
  }
}

// --- the host list ------------------------------------------------------

/**
 * One saved Mac.
 *
 * [id] is generated on the phone and never leaves it; it is what the selection and every per-host
 * setting hang off, so an alias the user renames does not orphan the token.
 */
public data class AgentHostEntry(
    val id: String,
    val alias: String,
    val url: String,
    val token: String,
    val mac: String,
)

/**
 * The host list's storage format: a JSON array, one object per Mac.
 *
 * JSON rather than the separator-delimited records the macros use, because this list grows fields
 * (a per-host refresh interval, a note) and an unknown key must be ignorable rather than fatal.
 * Written and read here rather than with `org.json` so that the round trip -- the part that would
 * silently lose every paired Mac if it were wrong -- has a test that runs without a device.
 */
public object HostCodec {
  public fun encode(hosts: List<AgentHostEntry>): String =
      hosts.joinToString(",", prefix = "[", postfix = "]") { host ->
        buildString {
          append('{')
          field("id", host.id)
          append(',')
          field("alias", host.alias)
          append(',')
          field("url", host.url)
          append(',')
          field("token", host.token)
          append(',')
          field("mac", host.mac)
          append('}')
        }
      }

  /**
   * Decodes what [encode] wrote. Anything unparseable decodes to an empty list.
   *
   * An entry with no URL is dropped: it would show as a host row that can never connect and offers
   * nothing to fix it.
   */
  public fun decode(text: String): List<AgentHostEntry> {
    val value = runCatching { JsonReader(text).readValue() }.getOrNull() ?: return emptyList()
    val array = value as? List<*> ?: return emptyList()
    return array.mapNotNull { element ->
      val o = element as? Map<*, *> ?: return@mapNotNull null
      val url = o.string("url")
      if (url.isBlank()) return@mapNotNull null
      AgentHostEntry(
          id = o.string("id").ifBlank { url },
          alias = o.string("alias"),
          url = url,
          token = o.string("token"),
          mac = o.string("mac"),
      )
    }
  }

  /**
   * The single-host settings, as a one-entry list.
   *
   * v1.1 stored one URL, one token, one MAC and one alias in four keys. Folding them into the list
   * rather than starting empty is the difference between an upgrade and a re-pairing: the token is
   * the part that cannot be typed back in.
   *
   * A blank URL means there was never a host, and the result is an empty list -- not a nameless
   * entry pointing at nothing.
   */
  public fun migrate(
      url: String,
      token: String,
      mac: String,
      alias: String,
  ): List<AgentHostEntry> {
    val trimmed = url.trim()
    if (trimmed.isBlank()) return emptyList()
    return listOf(
        AgentHostEntry(
            id = MIGRATED_ID,
            alias = alias.trim().ifBlank { aliasFor(trimmed) },
            url = trimmed,
            token = token.trim(),
            mac = mac.trim(),
        ))
  }

  /**
   * A default name for a host the user has not named: the address, without the noise.
   *
   * `http://atlas.coati-koi.ts.net:7411/` becomes `atlas`, which is what the top-bar chip has room
   * for and what the person calls the machine anyway.
   */
  public fun aliasFor(url: String): String =
      url.trim()
          .substringAfter("://")
          .substringBefore('/')
          .substringBefore(':')
          .substringBefore('.')
          .ifBlank { "mac" }

  /** The stable id of the host carried over from the single-host settings. */
  public const val MIGRATED_ID: String = "host-1"

  private fun Map<*, *>.string(key: String): String = (this[key] as? String).orEmpty()

  private fun StringBuilder.field(key: String, value: String) {
    append('"').append(key).append("\":")
    quote(value)
  }

  private fun StringBuilder.quote(value: String) {
    append('"')
    for (c in value) {
      when (c) {
        '"' -> append("\\\"")
        '\\' -> append("\\\\")
        '\n' -> append("\\n")
        '\r' -> append("\\r")
        '\t' -> append("\\t")
        else ->
            if (c < ' ') append("\\u").append(c.code.toString(16).padStart(4, '0')) else append(c)
      }
    }
    append('"')
  }
}

// --- HomeSpeaker's sources and recent broadcasts ------------------------

/** One HomeSpeaker broadcast, as `/v1/homespeaker` lists it in `last` and `recent`. */
public data class AgentLastBroadcast(
    val text: String,
    val target: String,
    val source: String,
    val at: String,
    val id: String = "",
)

/** One system speech voice reported by `GET /v1/homespeaker`. */
public data class AgentVoice(
    val id: String,
    val name: String,
    val lang: String,
)

/** One Google Home structure reported by `GET /v1/homespeaker`. */
public data class AgentHome(
    val id: String,
    val name: String,
)

/** One coding agent's hook and instruction status reported by `GET /v1/homespeaker`. */
public data class AgentHookStatus(
    val agent: String,
    val hookState: String,
    val speaksTwice: Boolean = false,
    val configuredByInstruction: Boolean = false,
)

/** One Beeper network reported by `GET /v1/homespeaker` (`reading`, `muted`, or `skipped`). */
public data class AgentBeeperNetwork(
    val key: String,
    val name: String,
    val state: String,
)

/** One cloned voice from `custom_voices`; its [id] is a valid `gemini_voice`. */
public data class AgentCustomVoice(val id: String, val name: String)

/**
 * The parts of `GET /v1/homespeaker` added in agent v1.10+: which senders HomeSpeaker speaks for,
 * and its newest broadcasts.
 *
 * Each switch is null when the key is absent -- an agent older than v1.10 -- so the dashboard hides
 * it instead of drawing a guess that the Mac would then refuse. That distinction is the whole
 * point, and it fails silently if wrong, so it is parsed here, where a JVM test reaches it.
 */
public data class HomeSpeakerSources(
    val announceClaudeCode: Boolean?,
    val announceAntigravity: Boolean?,
    val announceOpenCode: Boolean?,
    val slackEnabled: Boolean?,
    val googleChatEnabled: Boolean?,
    val beeperEnabled: Boolean?,
    val recent: List<AgentLastBroadcast>,
    val localEngine: String = "apple",
    val geminiVoice: String = "Kore",
    val hasGeminiKey: Boolean = false,
    val announcementStyle: String = "verbatim",
    val styleModel: String = "apple",
    val activeDoor: String = "app",
    val beeperAnnounce: String = "direct_and_mentions",
    val muteOwnMessages: Boolean? = null,
    val beeperNetworks: List<AgentBeeperNetwork> = emptyList(),
    val speakPhone: Boolean? = null,
    val phonePauseMedia: Boolean = false,
    val phoneHeadphonesOnly: Boolean = false,
    val phoneConnected: Boolean = false,
    val homeCastVoice: Boolean = false,
    val customVoices: List<AgentCustomVoice> = emptyList(),
    val customStylePrompt: String = "",
    val quietHoursActive: Boolean = false,
    val availableVoices: List<AgentVoice> = emptyList(),
    val structureId: String = "",
    val homes: List<AgentHome> = emptyList(),
    val accountEmail: String = "",
    val hasOAuthClient: Boolean = false,
    val hasAntigravityTokens: Boolean = false,
    val monitorRunning: Boolean = false,
    val lastPollAt: String = "",
    val slackIdentity: String = "",
    val activeGoogleChatBackend: String = "",
    val chatRuntimeError: String = "",
    val hasSlackToken: Boolean = false,
    val hasBeeperToken: Boolean = false,
    val hasChatAccess: Boolean = false,
    val gwsInstalled: Boolean = false,
    val gwsAccount: String = "",
    val googleChatSource: String = "auto",
    val pollInterval: Int = 30,
    val agents: List<AgentHookStatus> = emptyList(),
    val legacyLaunchAgent: Boolean = false,
    val customOAuthClientId: String = "",
    val hasCustomOAuthSecret: Boolean = false,
    val homeSpeakerVersion: String = "",
)

public object HomeSpeakerWire {
  /**
   * Reads the v1.10+ fields; anything unparseable reads as an older agent (all null, no history,
   * default local engine and style).
   */
  public fun sources(json: String): HomeSpeakerSources {
    val o =
        runCatching { JsonReader(json).readValue() as? Map<*, *> }.getOrNull()
            ?: emptyMap<Any, Any>()
    fun flag(key: String): Boolean? = o[key] as? Boolean
    fun str(key: String, def: String): String =
        (o[key] as? String)?.takeIf { it.isNotBlank() } ?: def
    val recent =
        (o["recent"] as? List<*>).orEmpty().mapNotNull { element ->
          val it = element as? Map<*, *> ?: return@mapNotNull null
          AgentLastBroadcast(
              id = it["id"] as? String ?: "",
              text = it["text"] as? String ?: "",
              target = it["target"] as? String ?: "",
              source = it["source"] as? String ?: "",
              at = it["at"] as? String ?: "",
          )
        }
    val beeperNetworks =
        (o["beeper_networks"] as? List<*>).orEmpty().mapNotNull { element ->
          val it = element as? Map<*, *> ?: return@mapNotNull null
          val key = (it["key"] as? String)?.trim().orEmpty()
          if (key.isEmpty()) return@mapNotNull null
          AgentBeeperNetwork(
              key = key,
              name = (it["name"] as? String)?.takeIf { n -> n.isNotBlank() } ?: key,
              state = (it["state"] as? String)?.takeIf { s -> s.isNotBlank() } ?: "reading",
          )
        }
    val customVoices =
        (o["custom_voices"] as? List<*>).orEmpty().mapNotNull { element ->
          val it = element as? Map<*, *> ?: return@mapNotNull null
          val id = (it["id"] as? String)?.trim().orEmpty()
          if (id.isEmpty()) return@mapNotNull null
          AgentCustomVoice(
              id = id,
              name = (it["name"] as? String)?.takeIf { n -> n.isNotBlank() } ?: id,
          )
        }
    val availableVoices =
        (o["available_voices"] as? List<*>).orEmpty().mapNotNull { element ->
          val it = element as? Map<*, *> ?: return@mapNotNull null
          val id = (it["id"] as? String)?.trim().orEmpty()
          if (id.isEmpty()) return@mapNotNull null
          AgentVoice(
              id = id,
              name = (it["name"] as? String)?.takeIf { n -> n.isNotBlank() } ?: id,
              lang = (it["lang"] as? String).orEmpty(),
          )
        }
    val homes =
        (o["homes"] as? List<*>).orEmpty().mapNotNull { element ->
          val it = element as? Map<*, *> ?: return@mapNotNull null
          val id = (it["id"] as? String)?.trim().orEmpty()
          if (id.isEmpty()) return@mapNotNull null
          AgentHome(
              id = id,
              name = (it["name"] as? String)?.takeIf { n -> n.isNotBlank() } ?: id,
          )
        }
    val agents =
        (o["agents"] as? List<*>).orEmpty().mapNotNull { element ->
          val it = element as? Map<*, *> ?: return@mapNotNull null
          val agent = (it["agent"] as? String)?.trim().orEmpty()
          if (agent.isEmpty()) return@mapNotNull null
          AgentHookStatus(
              agent = agent,
              hookState = (it["hook_state"] as? String).orEmpty(),
              speaksTwice = (it["speaks_twice"] as? Boolean) ?: false,
              configuredByInstruction = (it["configured_by_instruction"] as? Boolean) ?: false,
          )
        }
    val pollInterval = ((o["poll_interval"] as? Number)?.toInt() ?: 30).coerceAtLeast(5)
    return HomeSpeakerSources(
        announceClaudeCode = flag("announce_claude_code"),
        announceAntigravity = flag("announce_antigravity"),
        announceOpenCode = flag("announce_opencode"),
        slackEnabled = flag("slack_enabled"),
        googleChatEnabled = flag("google_chat_enabled"),
        beeperEnabled = flag("beeper_enabled"),
        recent = recent,
        localEngine = str("local_engine", "apple"),
        geminiVoice = str("gemini_voice", "Kore"),
        hasGeminiKey = flag("has_gemini_key") ?: false,
        announcementStyle = str("announcement_style", "verbatim"),
        styleModel = str("style_model", "apple"),
        activeDoor = str("active_door", "app"),
        beeperAnnounce = str("beeper_announce", "direct_and_mentions"),
        muteOwnMessages = flag("mute_own_messages"),
        beeperNetworks = beeperNetworks,
        speakPhone = flag("speak_phone"),
        phonePauseMedia = flag("phone_pause_media") ?: false,
        phoneHeadphonesOnly = flag("phone_headphones_only") ?: false,
        phoneConnected = flag("phone_connected") ?: false,
        homeCastVoice = flag("home_cast_voice") ?: false,
        customVoices = customVoices,
        customStylePrompt = (o["custom_style_prompt"] as? String).orEmpty(),
        quietHoursActive = flag("quiet_hours_active") ?: false,
        availableVoices = availableVoices,
        structureId = str("structure_id", ""),
        homes = homes,
        accountEmail = str("account_email", ""),
        hasOAuthClient = flag("has_oauth_client") ?: false,
        hasAntigravityTokens = flag("has_antigravity_tokens") ?: false,
        monitorRunning = flag("monitor_running") ?: false,
        lastPollAt = str("last_poll_at", ""),
        slackIdentity = str("slack_identity", ""),
        activeGoogleChatBackend = str("active_google_chat_backend", ""),
        chatRuntimeError = str("chat_runtime_error", ""),
        hasSlackToken = flag("has_slack_token") ?: false,
        hasBeeperToken = flag("has_beeper_token") ?: false,
        hasChatAccess = flag("has_chat_access") ?: false,
        gwsInstalled = flag("gws_installed") ?: false,
        gwsAccount = str("gws_account", ""),
        googleChatSource = str("google_chat_source", "auto"),
        pollInterval = pollInterval,
        agents = agents,
        legacyLaunchAgent = flag("legacy_launch_agent") ?: false,
        customOAuthClientId = str("custom_oauth_client_id", ""),
        hasCustomOAuthSecret = flag("has_custom_oauth_secret") ?: false,
        homeSpeakerVersion = str("home_speaker_version", ""),
    )
  }
}

/**
 * The smallest JSON reader that can read what [HostCodec] writes, and survive what it did not.
 *
 * Deliberately generic over the whole grammar rather than tuned to five string keys: a reader that
 * only understands the shape it wrote is a reader that throws the day someone adds a number.
 *
 * Public, not internal, because `BridgePolicy` reads the stored audit trail and is a separate
 * library for the same reason this one is -- a second hand-rolled JSON reader in the same app would
 * be a second place for the same bug.
 */
public class JsonReader(private val text: String) {
  private var index = 0

  /** The document, as `Map`, `List`, `String`, `Double`, `Boolean` or null. Throws on garbage. */
  public fun readValue(): Any? {
    skipSpace()
    val value = value()
    skipSpace()
    return value
  }

  private fun value(): Any? {
    return when (val c = peek()) {
      '{' -> obj()
      '[' -> array()
      '"' -> string()
      't' -> literal("true", true)
      'f' -> literal("false", false)
      'n' -> literal("null", null)
      else -> if (c == '-' || c.isDigit()) number() else error("unexpected '$c' at $index")
    }
  }

  private fun obj(): Map<String, Any?> {
    expect('{')
    val out = LinkedHashMap<String, Any?>()
    skipSpace()
    if (peek() == '}') {
      index++
      return out
    }
    while (true) {
      skipSpace()
      val key = string()
      skipSpace()
      expect(':')
      skipSpace()
      out[key] = value()
      skipSpace()
      when (val c = next()) {
        ',' -> Unit
        '}' -> return out
        else -> error("expected , or } but found '$c'")
      }
    }
  }

  private fun array(): List<Any?> {
    expect('[')
    val out = mutableListOf<Any?>()
    skipSpace()
    if (peek() == ']') {
      index++
      return out
    }
    while (true) {
      skipSpace()
      out += value()
      skipSpace()
      when (val c = next()) {
        ',' -> Unit
        ']' -> return out
        else -> error("expected , or ] but found '$c'")
      }
    }
  }

  private fun string(): String {
    expect('"')
    val out = StringBuilder()
    while (true) {
      when (val c = next()) {
        '"' -> return out.toString()
        '\\' ->
            when (val esc = next()) {
              '"' -> out.append('"')
              '\\' -> out.append('\\')
              '/' -> out.append('/')
              'b' -> out.append('\b')
              'f' -> out.append('\u000C')
              'n' -> out.append('\n')
              'r' -> out.append('\r')
              't' -> out.append('\t')
              'u' -> {
                val hex = text.substring(index, index + HEX_DIGITS)
                index += HEX_DIGITS
                out.append(hex.toInt(HEX_RADIX).toChar())
              }
              else -> error("bad escape '\\$esc'")
            }
        else -> out.append(c)
      }
    }
  }

  private fun number(): Double {
    val start = index
    if (peek() == '-') index++
    while (index < text.length && (text[index].isDigit() || text[index] in ".eE+-")) index++
    return text.substring(start, index).toDouble()
  }

  private fun <T> literal(word: String, value: T): T {
    require(text.startsWith(word, index)) { "expected $word at $index" }
    index += word.length
    return value
  }

  private fun skipSpace() {
    while (index < text.length && text[index].isWhitespace()) index++
  }

  private fun peek(): Char = if (index < text.length) text[index] else error("end of input")

  private fun next(): Char = peek().also { index++ }

  private fun expect(c: Char) {
    require(next() == c) { "expected '$c' at ${index - 1}" }
  }

  private companion object {
    const val HEX_DIGITS = 4
    const val HEX_RADIX = 16
  }
}

// --- deep links ---------------------------------------------------------

/**
 * `vitruvian-remote://<screen>`, the one URL this app answers to.
 *
 * Both the agent's ntfy `Click` header and the phone's own notifications use it, so the mapping
 * lives in one place rather than being spelled out at each end. Returned as a plain lower-case key
 * rather than a `Screen`: this file is deliberately free of the Compose-side model.
 */
public object DeepLink {
  public const val SCHEME: String = "vitruvian-remote"

  /** Every screen a link may name. Anything else is not a destination and returns null. */
  public val SCREENS: List<String> = listOf("home", "remote", "mac", "apps", "console", "hosts")

  /**
   * The screen a link names, or null.
   *
   * Tolerant of the shapes a notification service may hand back -- a trailing slash, a query
   * string, upper case, `vitruvian-remote:///console` from a URL builder that insisted on an empty
   * authority -- and null for every URL that is not ours, because opening the app on a random
   * screen because a link nearly matched is worse than ignoring it.
   */
  public fun screen(url: String?): String? {
    val text = url?.trim().orEmpty()
    if (!text.startsWith("$SCHEME://", ignoreCase = true)) return null
    val rest = text.substring(SCHEME.length + "://".length)
    val name =
        rest
            .substringBefore('?')
            .substringBefore('#')
            .trim('/')
            .lowercase()
            // Only the first segment names a screen; nothing consumes a deeper path yet.
            .substringBefore('/')
    return name.takeIf { it in SCREENS }
  }

  /**
   * The module a link names under Apps -- `claude` in `vitruvian-remote://apps/claude` -- or null.
   *
   * The agent's Claude prompt notification links there, and "Apps" alone would open whichever
   * module was last on screen, possibly the Gallery: the person tapped to answer a prompt and would
   * land somewhere else. Only a lower-case id of letters, digits and dashes is returned; the caller
   * still checks it names an installed module.
   */
  public fun appsModule(url: String?): String? {
    if (screen(url) != "apps") return null
    val rest = url.orEmpty().trim().substring(SCHEME.length + "://".length)
    val module =
        rest
            .substringBefore('?')
            .substringBefore('#')
            .trim('/')
            .lowercase()
            .split('/')
            .getOrNull(1)
            .orEmpty()
    return module.takeIf { it.isNotEmpty() && it.all { c -> c.isLetterOrDigit() || c == '-' } }
  }

  /** The link that opens [screen]. */
  public fun uriFor(screen: String): String = "$SCHEME://${screen.lowercase()}"

  private val PAIR_URL = Regex("^https?://[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?/?$")
  private val PAIR_CODE = Regex("^[0-9]{6}$")
  private val PAIR_NAME = Regex("[^A-Za-z0-9-]")

  /**
   * A pairing request from a QR code, or null.
   *
   * `vitruvian-remote://pair?code=482917&name=atlas&url=http%3A%2F%2F100.124.228.116%3A7411` --
   * built by the agent's `/pair` page, which the Mac's QR code opens. Strict on purpose: this link
   * can arrive from any web page, so a malformed field rejects the whole link rather than being
   * guessed at, and the address may only be a plain host and port, never a path or userinfo. The
   * caller still asks the person before pairing with it.
   */
  public fun pairing(url: String?): PairLink? {
    val text = url?.trim().orEmpty()
    val prefix = "$SCHEME://pair"
    if (!text.startsWith(prefix, ignoreCase = true)) return null
    val rest = text.substring(prefix.length).trimStart('/')
    if (!rest.startsWith("?")) return null
    val params =
        rest
            .substring(1)
            .substringBefore('#')
            .split('&')
            .filter { it.isNotEmpty() }
            .associate {
              val key = it.substringBefore('=')
              val value = java.net.URLDecoder.decode(it.substringAfter('=', ""), "UTF-8")
              key to value
            }
    val code = params["code"].orEmpty()
    val address = params["url"].orEmpty().trim()
    if (!PAIR_CODE.matches(code) || !PAIR_URL.matches(address)) return null
    val name = params["name"].orEmpty().replace(PAIR_NAME, "").take(32)
    return PairLink(url = address.trimEnd('/'), code = code, name = name)
  }
}

/** What a pairing QR code carries: where the Mac is, the one-time code, and what to call it. */
public data class PairLink(val url: String, val code: String, val name: String)

// --- Sony Google TV (`/v1/tv`) ------------------------------------------

/** State of the Sony Google TV reported by `GET /v1/tv` and `POST /v1/tv`. */
public data class AgentTv(
    val available: Boolean,
    val connected: Boolean,
    val awake: Boolean,
    val dreaming: Boolean,
    val foreground: String,
    val memAvailableMb: Int,
    val address: String,
    val reason: String = "",
)

public object TvWire {
  public const val DEFAULT_ADDRESS: String = "192.168.86.31:5555"

  /** Parses `GET /v1/tv` and `POST /v1/tv` responses without `org.json` so JVM unit tests run. */
  public fun parse(json: String): AgentTv {
    val o =
        runCatching { JsonReader(json).readValue() as? Map<*, *> }.getOrNull()
            ?: emptyMap<Any, Any>()
    fun flag(key: String): Boolean = (o[key] as? Boolean) ?: false
    fun str(key: String, def: String = ""): String =
        (o[key] as? String)?.takeIf { it.isNotBlank() } ?: def
    val memMb = ((o["mem_available_mb"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
    return AgentTv(
        available = flag("available"),
        connected = flag("connected"),
        awake = flag("awake"),
        dreaming = flag("dreaming"),
        foreground = str("foreground", "Standby"),
        memAvailableMb = memMb,
        address = str("address", DEFAULT_ADDRESS),
        reason = (o["reason"] as? String).orEmpty(),
    )
  }
}
