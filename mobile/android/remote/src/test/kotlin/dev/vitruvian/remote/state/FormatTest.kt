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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The conversions that fail quietly.
 *
 * Every case here is a boundary: the second a "min" becomes an "h", the byte where GB takes over
 * from MB, the decimal that must not print as `.0`. None of them throws when it is wrong -- the
 * screen just reads badly -- so the boundaries are pinned rather than watched.
 */
public class FormatTest {

  private val now = Instant.parse("2026-09-05T12:00:00Z").toEpochMilli()

  private fun ago(seconds: Long): String =
      Format.relativeTime(Instant.ofEpochMilli(now).minusSeconds(seconds).toString(), now)

  @Test
  public fun relativeTimeBuckets() {
    assertEquals("just now", ago(0))
    assertEquals("just now", ago(59))
    assertEquals("1 min ago", ago(60))
    assertEquals("3 min ago", ago(3 * 60))
    assertEquals("59 min ago", ago(3599))
    assertEquals("1 h ago", ago(3600))
    assertEquals("2 h ago", ago(2 * 3600))
    assertEquals("23 h ago", ago(86_399))
    assertEquals("yesterday", ago(86_400))
    assertEquals("yesterday", ago(2 * 86_400 - 1))
    assertEquals("2 d ago", ago(2 * 86_400))
    assertEquals("5 d ago", ago(5 * 86_400))
  }

  /** A Mac a few seconds ahead of the phone must not be reported as being in the future. */
  @Test
  public fun clockSkewReadsAsNow() {
    assertEquals("just now", ago(-30))
  }

  /** Go writes RFC3339 with a numeric offset; a plain trailing Z has to work too. */
  @Test
  public fun acceptsBothRfc3339Forms() {
    assertEquals("1 h ago", Format.relativeTime("2026-09-05T04:00:00-07:00", now))
    assertEquals("1 h ago", Format.relativeTime("2026-09-05T11:00:00Z", now))
  }

  /** Unreadable in, blank out -- so the caller can print what it was given instead. */
  @Test
  public fun unparseableIsBlank() {
    assertEquals("", Format.relativeTime("", now))
    assertEquals("", Format.relativeTime("yesterday afternoon", now))
  }

  @Test
  public fun shortPathUnderHome() {
    val p = Format.shortPath("/Users/james/Workspace/gh/vitruvian-core", "/Users/james")
    assertEquals("vitruvian-core", p.name)
    assertEquals("~/…/gh", p.parent)
  }

  @Test
  public fun shortPathDirectlyInHome() {
    val p = Format.shortPath("/Users/james/code", "/Users/james")
    assertEquals("code", p.name)
    assertEquals("~", p.parent)
  }

  @Test
  public fun shortPathWithoutHome() {
    val p = Format.shortPath("/opt/homebrew/share/android", null)
    assertEquals("android", p.name)
    assertEquals("…/share", p.parent)
    val root = Format.shortPath("/opt", null)
    assertEquals("opt", root.name)
    assertEquals("/", root.parent)
  }

  @Test
  public fun shortPathIgnoresTrailingSlash() {
    assertEquals("core", Format.shortPath("/Users/james/core/", "/Users/james").name)
  }

  @Test
  public fun homeComesFromTheClaudeDirectory() {
    assertEquals("/Users/james", Format.homeFor("/Users/james/.claude/projects/-Users-james-core"))
    // No .claude in the path: the /Users/<name> shape is the fallback.
    assertEquals("/Users/ada", Format.homeFor("/Users/ada/Workspace/thing"))
    assertNull(Format.homeFor("/opt/tools"))
    assertNull(Format.homeFor(null))
  }

  /** Decimal, matching Finder and `ollama list`, and never a trailing `.0`. */
  @Test
  public fun bytesAreDecimalAndTrimmed() {
    assertEquals("128 GB", Format.formatBytes(128_000_000_000L))
    assertEquals("9.6 GB", Format.formatBytes(9_600_000_000L))
    assertEquals("4 GB", Format.formatBytes(4_000_000_000L))
    assertEquals("512 MB", Format.formatBytes(512_000_000L))
    assertEquals("1.2 TB", Format.formatBytes(1_210_000_000_000L))
    assertEquals("4 KB", Format.formatBytes(4_000L))
    assertEquals("512 B", Format.formatBytes(512L))
  }

  /** The pair shares the total's unit, so the two numbers stay comparable. */
  @Test
  public fun bytesPairSharesOneUnit() {
    assertEquals("74 / 128 GB", Format.bytesPair(74_000_000_000L, 128_000_000_000L))
    assertEquals("0.7 / 128 GB", Format.bytesPair(740_000_000L, 128_000_000_000L))
  }

  @Test
  public fun wattsDropTheTrailingZero() {
    assertEquals("0 W", Format.watts(0.0))
    assertEquals("6.4 W", Format.watts(6.44))
    assertEquals("18 W", Format.watts(17.98))
  }

  @Test
  public fun containerTitlesAreTheHeadlineNotTheSentence() {
    assertEquals(
        "Docker daemon not running",
        Format.containerTitle(
            "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"),
    )
    assertEquals(
        "Podman machine not running",
        Format.containerTitle("Cannot connect to Podman. Please verify the connection"),
    )
    assertEquals("Containers unavailable", Format.containerTitle("exit status 127"))
  }

  @Test
  public fun clipBreaksAtAWord() {
    val reason =
        "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. " +
            "Is the docker daemon running?"
    val clipped = Format.clip(reason)
    assertEquals("Cannot connect to the Docker daemon at…", clipped)
    // Short enough already: untouched, and no ellipsis added.
    assertEquals("exit status 127", Format.clip("exit status 127"))
  }

  @Test
  public fun shortHostDropsTheDomain() {
    assertEquals("james-macbook-pro", Format.shortHost("James-MacBook-Pro.local"))
    assertEquals("atlas", Format.shortHost("atlas.coati-koi.ts.net"))
  }

  /** A subtitle built from optional parts must never show a dangling separator. */
  @Test
  public fun partsSkipsTheBlanks() {
    assertEquals("battery 31°", Format.parts("battery 31°", "", null))
    assertEquals("load 4.55 · 16 cores", Format.parts("load 4.55", "16 cores"))
    assertEquals("", Format.parts(null, "", "  "))
  }
}
