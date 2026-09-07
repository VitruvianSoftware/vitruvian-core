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

/**
 * The smallest JSON reader that can read what [HostCodec] writes, and survive what it did not.
 *
 * Deliberately generic over the whole grammar rather than tuned to five string keys: a reader that
 * only understands the shape it wrote is a reader that throws the day someone adds a number.
 */
internal class JsonReader(private val text: String) {
  private var index = 0

  fun readValue(): Any? {
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

  /** The link that opens [screen]. */
  public fun uriFor(screen: String): String = "$SCHEME://${screen.lowercase()}"
}
