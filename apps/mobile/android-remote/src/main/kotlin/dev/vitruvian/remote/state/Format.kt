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
import java.util.Locale
import kotlin.math.roundToLong

/**
 * Turning what the Mac says into what a person reads.
 *
 * Split out of [RemoteState] and free of Android imports for the same reason as `HidCodes` and
 * `WakeOnLan`: these are the conversions that fail QUIETLY. A timestamp shown raw, a path shown in
 * full and a size in the wrong base are all perfectly valid strings -- nothing throws, nothing
 * logs, and the screen simply becomes unreadable. A plain JVM test can pin every boundary here
 * without a phone or an emulator in the room.
 */
public object Format {

  // --- sizes ------------------------------------------------------------
  //
  // DECIMAL, not binary. macOS reports storage and memory in powers of ten
  // (a "512 GB" SSD is 512e9 bytes in Finder) and so does `ollama list`, so
  // dividing by 1024 here would print a number that agrees with nothing the
  // user can see on the machine itself.

  private const val KB = 1_000.0
  private const val MB = 1_000_000.0
  private const val GB = 1_000_000_000.0
  private const val TB = 1_000_000_000_000.0

  // RAM is the exception. macOS reports memory in powers of two and labels
  // it GB ("128 GB" in About This Mac is 137,438,953,472 bytes), as does
  // Lima for its VMs. Printing RAM in decimal gave "137.4 GB" for a machine
  // every other surface calls 128.
  private const val GIB = 1024.0 * 1024.0 * 1024.0

  /** RAM: `128 GB`, `4 GB`, `9.5 GB` - binary, labelled the way macOS labels it. */
  public fun memoryBytes(bytes: Long): String = "${sized(bytes / GIB)} GB"

  /** RAM used of total: `80 / 128 GB`. */
  public fun memoryPair(used: Long, total: Long): String =
      "${sized(used / GIB)} / ${sized(total / GIB)} GB"

  /**
   * One decimal while the number is small enough for it to matter, none once it is not: `9.6`,
   * `17.1`, but `128` and `137`. A tenth of a gigabyte is noise next to a hundred of them.
   */
  private fun sized(value: Double): String =
      if (value >= 100) value.roundToLong().toString() else decimal(value)

  /** `128 GB`, `9.6 GB`, `512 MB`. One decimal at most, and never a trailing `.0`. */
  public fun formatBytes(bytes: Long): String {
    val unit = unitFor(bytes)
    return "${inUnit(bytes, unit)} $unit"
  }

  /**
   * `74 / 128 GB` - a used-of-total pair sharing one unit.
   *
   * The unit comes from the TOTAL so the two numbers stay comparable at a glance. Printing each
   * with its own unit gives "740 MB / 128 GB", where the eye reads 740 as the larger figure.
   */
  public fun bytesPair(used: Long, total: Long): String {
    val unit = unitFor(total)
    return "${inUnit(used, unit)} / ${inUnit(total, unit)} $unit"
  }

  /** `0`, `6.4`, `18.2` - one decimal, trailing `.0` dropped. */
  public fun decimal(value: Double): String {
    val rounded = (value * 10).roundToLong() / 10.0
    val text = String.format(Locale.ROOT, "%.1f", rounded)
    return text.removeSuffix(".0")
  }

  /** Watts as the plates print them: `0 W`, `6.4 W`. */
  public fun watts(value: Double): String = "${decimal(value)} W"

  private fun unitFor(bytes: Long): String =
      when {
        bytes >= TB -> "TB"
        bytes >= GB -> "GB"
        bytes >= MB -> "MB"
        bytes >= KB -> "KB"
        else -> "B"
      }

  private fun inUnit(bytes: Long, unit: String): String =
      when (unit) {
        "TB" -> sized(bytes / TB)
        "GB" -> sized(bytes / GB)
        "MB" -> decimal(bytes / MB)
        "KB" -> decimal(bytes / KB)
        else -> bytes.toString()
      }

  // --- time -------------------------------------------------------------

  /**
   * How long ago, in the words a person would use.
   *
   * Blank when the string is not a timestamp this can read, so the caller can fall back to what it
   * was given rather than printing a confident "just now" for something it failed to parse.
   */
  public fun relativeTime(iso: String, now: Long): String {
    val instant = parseInstant(iso) ?: return ""
    val seconds = (now - instant.toEpochMilli()) / 1000
    // A clock skew of a few seconds between phone and Mac is ordinary and
    // must not print "in 4 seconds"; anything in the future reads as now.
    if (seconds < MINUTE) return "just now"
    if (seconds < HOUR) return "${seconds / MINUTE} min ago"
    if (seconds < DAY) return "${seconds / HOUR} h ago"
    if (seconds < 2 * DAY) return "yesterday"
    return "${seconds / DAY} d ago"
  }

  private fun parseInstant(iso: String): Instant? {
    val text = iso.trim()
    if (text.isEmpty()) return null
    // Go's RFC3339 carries a numeric offset, which OffsetDateTime reads and
    // ISO_INSTANT does not; the Instant path covers a plain trailing Z.
    return runCatching { OffsetDateTime.parse(text).toInstant() }.getOrNull()
        ?: runCatching { Instant.parse(text) }.getOrNull()
  }

  // --- paths ------------------------------------------------------------

  /**
   * A path split into the part worth reading and the part worth hinting at.
   *
   * [name] is the last segment -- the project, the directory, the thing being named -- and [parent]
   * is where it lives, elided in the middle. A full path in a 55 dp row is an ellipsis with a few
   * characters of `/Users/` in front of it.
   */
  public data class ShortPath(val name: String, val parent: String)

  public fun shortPath(path: String, home: String?): ShortPath {
    val clean = path.trim().trimEnd('/')
    if (clean.isEmpty()) return ShortPath("", "")
    val name = clean.substringAfterLast('/')
    val parentPath = clean.substringBeforeLast('/', missingDelimiterValue = "")
    return ShortPath(name, elide(parentPath, home))
  }

  /** `~/…/design-system`, `/…/share`, `~`, `/`. */
  private fun elide(parentPath: String, home: String?): String {
    if (parentPath.isEmpty()) return "/"
    val underHome = home?.trimEnd('/')?.takeIf { it.isNotEmpty() && parentPath.startsWith(it) }
    val root = if (underHome != null) "~" else ""
    val rest =
        if (underHome != null) parentPath.removePrefix(underHome).trim('/')
        else parentPath.trim('/')
    if (rest.isEmpty()) return if (root.isEmpty()) "/" else root
    val segments = rest.split('/')
    val last = segments.last()
    val prefix = if (root.isEmpty()) "" else "$root/"
    return if (segments.size == 1) "$prefix$last" else "$prefix…/$last"
  }

  /**
   * The user's home directory, inferred from a path the agent gave us.
   *
   * The agent reports session directories under `~/.claude/projects`, so the part before
   * `/.claude/` IS the home directory -- no guessing and no `/Users/<name>` assumption. That
   * assumption is the fallback, for a path that does not go through `.claude` at all.
   */
  public fun homeFor(path: String?): String? {
    val text = path?.trim().orEmpty()
    if (text.isEmpty()) return null
    val claude = text.indexOf("/.claude/")
    if (claude > 0) return text.take(claude)
    val segments = text.trim('/').split('/')
    if (segments.size >= 2 && segments[0] == "Users") return "/Users/${segments[1]}"
    return null
  }

  // --- reasons ----------------------------------------------------------

  /**
   * A container runtime's own error, as a row title.
   *
   * The raw text is a 200-character sentence about a socket, which is the truth but not the
   * headline. The headline is that the daemon is not running; the sentence goes underneath, where
   * someone debugging it can still read it.
   */
  public fun containerTitle(reason: String): String =
      when {
        reason.contains("cannot connect to the docker daemon", ignoreCase = true) ->
            "Docker daemon not running"
        reason.contains("podman", ignoreCase = true) &&
            reason.contains("connect", ignoreCase = true) -> "Podman machine not running"
        else -> "Containers unavailable"
      }

  /** One line's worth of a long reason, cut at a word rather than mid-word. */
  public fun clip(text: String, max: Int = CLIP_MAX): String {
    val line = text.trim().lineSequence().first().trim()
    if (line.length <= max) return line
    val cut = line.take(max)
    val space = cut.lastIndexOf(' ')
    // A "word" longer than the whole budget (a path, a socket URL) has no
    // space to break at; cutting mid-token beats printing nothing.
    return (if (space > max / 2) cut.take(space) else cut).trimEnd(' ', ',', ':', ';', '.') + "…"
  }

  /** `james-macbook-pro` from `James-MacBook-Pro.local`. */
  public fun shortHost(hostname: String): String =
      hostname.trim().substringBefore('.').lowercase(Locale.ROOT)

  /** Joins the parts that have something to say, and only those. */
  public fun parts(vararg values: String?): String =
      values.filterNot { it.isNullOrBlank() }.joinToString(" · ")

  private const val MINUTE = 60L
  private const val HOUR = 3_600L
  private const val DAY = 86_400L

  /** Where a one-line reason gets cut. Wide enough for a sentence, short enough for a row. */
  public const val CLIP_MAX: Int = 60
}
