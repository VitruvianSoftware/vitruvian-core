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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The three formats that fail in silence.
 *
 * Each case here is a shape that produced no error and no exception on the way to being wrong: a
 * dropped output line, a host list that decoded to nothing, a link that opened the wrong screen.
 */
public class WireTest {

  // --- server-sent events ------------------------------------------------

  private fun parse(vararg chunks: String): List<SseEvent> {
    val parser = SseParser()
    val out = mutableListOf<SseEvent>()
    chunks.forEach { parser.feed(it) { event -> out += event } }
    parser.close { event -> out += event }
    return out
  }

  @Test
  public fun `reads one line event`() {
    val events = parse("event: line\ndata: {\"stream\":\"stdout\",\"text\":\"hello\"}\n\n")
    assertEquals(1, events.size)
    assertEquals("line", events[0].name)
    assertEquals("{\"stream\":\"stdout\",\"text\":\"hello\"}", events[0].data)
  }

  @Test
  public fun `ignores keepalive comments and blank lines between events`() {
    val events =
        parse(
            ": keepalive\n",
            "\n",
            "event: line\ndata: one\n\n",
            ": keepalive\n\n",
            "event: exit\ndata: {\"exit_code\":0}\n\n",
        )
    // The comments and the stray blank line contribute nothing: two events, in
    // order. A comment counted as an event would deliver a blank output line
    // every 15 seconds for the length of a build.
    assertEquals(
        listOf(SseEvent("line", "one"), SseEvent("exit", "{\"exit_code\":0}")),
        events,
    )
  }

  @Test
  public fun `joins a data field split across two chunks`() {
    // The case the parser exists for: a socket read that ends mid-payload.
    // A reader that treated a chunk as a line would lose "rest of the line"
    // entirely, with nothing anywhere to say a line had gone missing.
    val events = parse("event: line\ndata: start of ", "the line\n\n")
    assertEquals(listOf(SseEvent("line", "start of the line")), events)
  }

  @Test
  public fun `joins an event split mid-field-name`() {
    val events = parse("eve", "nt: ex", "it\nda", "ta: {\"exit_code\":3}\n\n")
    assertEquals(listOf(SseEvent("exit", "{\"exit_code\":3}")), events)
  }

  @Test
  public fun `concatenates repeated data lines with a newline`() {
    val events = parse("event: line\ndata: first\ndata: second\n\n")
    assertEquals(listOf(SseEvent("line", "first\nsecond")), events)
  }

  @Test
  public fun `accepts carriage returns and a missing space after the colon`() {
    val events = parse("event:line\r\ndata:tight\r\n\r\n")
    assertEquals(listOf(SseEvent("line", "tight")), events)
  }

  @Test
  public fun `dispatches a final event with no trailing blank line`() {
    // The agent's exit event is always last; a stream that ends without the
    // blank line would otherwise throw away the exit code.
    val events = parse("event: exit\ndata: {\"exit_code\":7}\n")
    assertEquals(listOf(SseEvent("exit", "{\"exit_code\":7}")), events)
  }

  @Test
  public fun `emits nothing for a stream of only comments`() {
    assertTrue(parse(": keepalive\n: keepalive\n").isEmpty())
  }

  // --- the host list -----------------------------------------------------

  private val hosts =
      listOf(
          AgentHostEntry("host-1", "atlas", "http://100.64.0.12:7411", "deadbeef", "aa:bb:cc"),
          AgentHostEntry("host-2", "forge", "forge.ts.net", "", ""),
      )

  @Test
  public fun `host list survives a round trip`() {
    assertEquals(hosts, HostCodec.decode(HostCodec.encode(hosts)))
  }

  @Test
  public fun `host list round trips an alias with quotes and a backslash`() {
    // A name is free text typed on a phone. An unescaped quote here would
    // produce a document that decodes to an empty list -- every paired Mac
    // gone, with no error at any point.
    val awkward =
        listOf(AgentHostEntry("host-1", "james' \"mac\" \\ office", "10.0.0.2", "tok", ""))
    assertEquals(awkward, HostCodec.decode(HostCodec.encode(awkward)))
  }

  @Test
  public fun `empty list round trips`() {
    assertEquals(emptyList<AgentHostEntry>(), HostCodec.decode(HostCodec.encode(emptyList())))
  }

  @Test
  public fun `unknown keys are ignored rather than fatal`() {
    val text = """[{"id":"h","alias":"a","url":"u","token":"t","mac":"m","refreshSeconds":5}]"""
    assertEquals(
        listOf(AgentHostEntry("h", "a", "u", "t", "m")),
        HostCodec.decode(text),
    )
  }

  @Test
  public fun `garbage decodes to nothing rather than throwing`() {
    assertEquals(emptyList<AgentHostEntry>(), HostCodec.decode("not json at all"))
    assertEquals(emptyList<AgentHostEntry>(), HostCodec.decode(""))
    assertEquals(emptyList<AgentHostEntry>(), HostCodec.decode("[{\"id\":"))
  }

  @Test
  public fun `an entry with no url is dropped`() {
    assertEquals(
        emptyList<AgentHostEntry>(),
        HostCodec.decode("""[{"id":"h","alias":"a","url":"","token":"t","mac":""}]"""),
    )
  }

  @Test
  public fun `migration folds the four old keys into one host`() {
    val migrated =
        HostCodec.migrate(
            url = "100.64.0.12:7411",
            token = "cafebabe",
            mac = "aa:bb:cc:dd:ee:ff",
            alias = "atlas",
        )
    assertEquals(
        listOf(
            AgentHostEntry(
                HostCodec.MIGRATED_ID,
                "atlas",
                "100.64.0.12:7411",
                "cafebabe",
                "aa:bb:cc:dd:ee:ff")),
        migrated,
    )
  }

  @Test
  public fun `migration names the host after its address when there was no alias`() {
    // v1.1 had no alias field at all, so this is the ordinary upgrade path,
    // not the exception.
    val migrated =
        HostCodec.migrate(
            url = "http://atlas.coati-koi.ts.net:7411/", token = "t", mac = "", alias = "")
    assertEquals("atlas", migrated.single().alias)
  }

  @Test
  public fun `nothing to migrate when no agent was ever configured`() {
    assertEquals(emptyList<AgentHostEntry>(), HostCodec.migrate("", "", "", ""))
    assertEquals(emptyList<AgentHostEntry>(), HostCodec.migrate("   ", "tok", "mac", "alias"))
  }

  @Test
  public fun `a migrated host survives the round trip that stores it`() {
    val migrated = HostCodec.migrate("10.0.0.2", "tok", "aa:bb", "atlas")
    assertEquals(migrated, HostCodec.decode(HostCodec.encode(migrated)))
  }

  // --- deep links --------------------------------------------------------

  @Test
  public fun `every screen has a link that round trips`() {
    DeepLink.SCREENS.forEach { screen ->
      assertEquals(screen, DeepLink.screen(DeepLink.uriFor(screen)))
    }
  }

  @Test
  public fun `link parsing tolerates case slashes and a query string`() {
    assertEquals("console", DeepLink.screen("vitruvian-remote://console/"))
    assertEquals("console", DeepLink.screen("VITRUVIAN-REMOTE://Console"))
    assertEquals("hosts", DeepLink.screen("vitruvian-remote://hosts?from=ntfy"))
    assertEquals("mac", DeepLink.screen("  vitruvian-remote://mac  "))
    // A URL builder that insisted on an empty authority.
    assertEquals("apps", DeepLink.screen("vitruvian-remote:///apps"))
  }

  @Test
  public fun `a link that is not ours opens nothing`() {
    // Opening the app on a screen because a link nearly matched is worse than
    // ignoring it: the notification would have said one thing and shown
    // another.
    assertNull(DeepLink.screen(null))
    assertNull(DeepLink.screen(""))
    assertNull(DeepLink.screen("https://example.com/console"))
    assertNull(DeepLink.screen("vitruvian-remote://nowhere"))
    assertNull(DeepLink.screen("vitruvian-remote://"))
    assertNull(DeepLink.screen("vitruvianremote://console"))
  }
}
