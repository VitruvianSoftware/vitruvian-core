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
  public fun `an apps link can name the module to open`() {
    // The agent's Claude prompt notification: it must land on the Claude
    // dashboard, not on whichever module was last open.
    assertEquals("apps", DeepLink.screen("vitruvian-remote://apps/claude"))
    assertEquals("claude", DeepLink.appsModule("vitruvian-remote://apps/claude"))
    assertEquals("claude", DeepLink.appsModule("vitruvian-remote:///Apps/Claude/?from=ntfy"))
    assertNull(DeepLink.appsModule("vitruvian-remote://apps"))
    assertNull(DeepLink.appsModule("vitruvian-remote://console/claude"))
    assertNull(DeepLink.appsModule("vitruvian-remote://apps/../x y"))
    assertNull(DeepLink.appsModule(null))
  }

  @Test
  public fun `the Antigravity link opens its dashboard`() {
    // What the agent's ntfy push for a finished Antigravity run carries (API v1.7).
    assertEquals("apps", DeepLink.screen("vitruvian-remote://apps/antigravity"))
    assertEquals("antigravity", DeepLink.appsModule("vitruvian-remote://apps/antigravity"))
    assertEquals(
        "antigravity", DeepLink.appsModule("vitruvian-remote://apps/Antigravity/?from=ntfy"))
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

  // The exact link the agent's /pair page builds; pairpage_test.go asserts the same string, so the
  // Mac and the phone cannot drift apart on its shape.
  private val pairFixture =
      "vitruvian-remote://pair?code=482917&name=atlas&url=http%3A%2F%2F100.124.228.116%3A7411"

  @Test
  public fun pairingLinkFromTheAgentParses() {
    assertEquals(
        PairLink(url = "http://100.124.228.116:7411", code = "482917", name = "atlas"),
        DeepLink.pairing(pairFixture),
    )
    // It is not a screen: the screen router must leave it alone.
    assertNull(DeepLink.screen(pairFixture))
  }

  @Test
  public fun pairingLinkToleratesShapeButNotContent() {
    assertEquals(
        "482917",
        DeepLink.pairing("vitruvian-remote://pair/?code=482917&url=http://atlas:7411/")?.code)
    assertEquals(
        "http://atlas:7411",
        DeepLink.pairing("vitruvian-remote://pair?code=482917&url=http://atlas:7411/")?.url)
    // A name is optional and scrubbed to letters, digits and dashes.
    assertEquals(
        "", DeepLink.pairing("vitruvian-remote://pair?code=482917&url=http://atlas:7411")?.name)
    assertEquals(
        "evilname",
        DeepLink.pairing(
                "vitruvian-remote://pair?code=482917&url=http://atlas:7411&name=%3Cevil%3E+name")
            ?.name)
  }

  @Test
  public fun pairingLinkRejectsAnythingOdd() {
    listOf(
            null,
            "",
            "vitruvian-remote://hosts",
            "vitruvian-remote://pair",
            "vitruvian-remote://pairing?code=482917&url=http://atlas:7411",
            "https://example.com/pair?code=482917&url=http://atlas:7411",
            "vitruvian-remote://pair?code=48291&url=http://atlas:7411",
            "vitruvian-remote://pair?code=4829170&url=http://atlas:7411",
            "vitruvian-remote://pair?code=48291a&url=http://atlas:7411",
            "vitruvian-remote://pair?code=482917",
            "vitruvian-remote://pair?code=482917&url=ftp://atlas:7411",
            "vitruvian-remote://pair?code=482917&url=http://user@atlas:7411",
            "vitruvian-remote://pair?code=482917&url=http://atlas:7411/evil",
            "vitruvian-remote://pair?code=482917&url=http://atlas:7411?x=1",
        )
        .forEach { assertNull(it, DeepLink.pairing(it)) }
  }

  // --- HomeSpeaker sources and recent broadcasts (agent v1.10) -------------

  /** What a v1.10 agent sends: every switch, and the history newest first. */
  private val homeSpeakerV110 =
      """
      {"available":true,"enabled":true,"speak_home":true,"speak_local":false,
       "announce_claude_code":false,"announce_antigravity":true,"announce_opencode":false,
       "slack_enabled":true,"google_chat_enabled":false,"beeper_enabled":true,
       "last":{"text":"Build is green.","target":"Kitchen speaker","source":"Claude Code","at":"2026-10-17T09:00:00Z"},
       "recent":[
         {"text":"Build is green.","target":"Kitchen speaker","source":"Claude Code","at":"2026-10-17T09:00:00Z"},
         {"text":"New message from Ana","target":"Kitchen speaker","source":"Slack","at":"2026-10-17T08:59:00Z"}
       ]}
      """
          .trimIndent()

  @Test
  public fun `homespeaker reads every source switch and the recent list in order`() {
    val s = HomeSpeakerWire.sources(homeSpeakerV110)
    assertEquals(false, s.announceClaudeCode)
    assertEquals(true, s.announceAntigravity)
    assertEquals(false, s.announceOpenCode)
    assertEquals(true, s.slackEnabled)
    assertEquals(false, s.googleChatEnabled)
    assertEquals(true, s.beeperEnabled)
    assertEquals(
        listOf(
            AgentLastBroadcast(
                "Build is green.", "Kitchen speaker", "Claude Code", "2026-10-17T09:00:00Z"),
            AgentLastBroadcast(
                "New message from Ana", "Kitchen speaker", "Slack", "2026-10-17T08:59:00Z"),
        ),
        s.recent)
  }

  /**
   * An agent older than v1.10 sends none of these. Null -- not false -- is what hides the switches:
   * a false would draw "off" for Claude Code on a Mac that is in fact speaking every reply.
   */
  @Test
  public fun `homespeaker from an older agent reads as unknown, not off`() {
    val old =
        """{"available":true,"enabled":true,"speak_home":true,"speak_local":false,""" +
            """"last":{"text":"hi","target":"Kitchen","source":"Say","at":"2026-10-17T09:00:00Z"}}"""
    val s = HomeSpeakerWire.sources(old)
    assertNull(s.announceClaudeCode)
    assertNull(s.announceAntigravity)
    assertNull(s.announceOpenCode)
    assertNull(s.slackEnabled)
    assertNull(s.googleChatEnabled)
    assertNull(s.beeperEnabled)
    assertTrue(s.recent.isEmpty())
  }

  @Test
  public fun `homespeaker survives odd shapes without inventing switches`() {
    listOf("", "not json", "[]", """{"announce_claude_code":"yes","recent":{"text":"x"}}""")
        .forEach { json ->
          val s = HomeSpeakerWire.sources(json)
          assertNull(json, s.announceClaudeCode)
          assertTrue(json, s.recent.isEmpty())
        }
    // One bad entry in the list is skipped, not fatal for the rest.
    val mixed = HomeSpeakerWire.sources("""{"recent":[42,{"text":"ok"}]}""")
    assertEquals(listOf(AgentLastBroadcast("ok", "", "", "")), mixed.recent)
  }

  @Test
  public fun `homespeaker reads v1_11 local engine, gemini voice, style and active door with safe defaults`() {
    val old = HomeSpeakerWire.sources(homeSpeakerV110)
    assertEquals("apple", old.localEngine)
    assertEquals("Kore", old.geminiVoice)
    assertEquals(false, old.hasGeminiKey)
    assertEquals("verbatim", old.announcementStyle)
    assertEquals("apple", old.styleModel)
    assertEquals("app", old.activeDoor)
    assertEquals("direct_and_mentions", old.beeperAnnounce)
    assertNull(old.muteOwnMessages)
    assertTrue(old.beeperNetworks.isEmpty())

    val v111 =
        HomeSpeakerWire.sources(
            """{"local_engine":"gemini","gemini_voice":"Fenrir","has_gemini_key":true,""" +
                """"announcement_style":"briefing","style_model":"gemini","active_door":"extension",""" +
                """"beeper_announce":"all","mute_own_messages":true,""" +
                """"beeper_networks":[{"key":"whatsapp","name":"WhatsApp","state":"reading"},{"key":"googlechat","name":"Google Chat","state":"skipped"}]}""")
    assertEquals("gemini", v111.localEngine)
    assertEquals("Fenrir", v111.geminiVoice)
    assertEquals(true, v111.hasGeminiKey)
    assertEquals("briefing", v111.announcementStyle)
    assertEquals("gemini", v111.styleModel)
    assertEquals("extension", v111.activeDoor)
    assertEquals("all", v111.beeperAnnounce)
    assertEquals(true, v111.muteOwnMessages)
    assertEquals(
        listOf(
            AgentBeeperNetwork("whatsapp", "WhatsApp", "reading"),
            AgentBeeperNetwork("googlechat", "Google Chat", "skipped"),
        ),
        v111.beeperNetworks)
    assertNull(v111.speakPhone)
    assertEquals(false, v111.phonePauseMedia)
    assertEquals(false, v111.phoneHeadphonesOnly)
    assertEquals(false, v111.phoneConnected)

    val v112 =
        HomeSpeakerWire.sources(
            """{"speak_phone":true,"phone_pause_media":true,"phone_headphones_only":true,"phone_connected":true}""")
    assertEquals(true, v112.speakPhone)
    assertEquals(true, v112.phonePauseMedia)
    assertEquals(true, v112.phoneHeadphonesOnly)
    assertEquals(true, v112.phoneConnected)
  }

  @Test
  public fun `homespeaker reads cast voice, cloned voices and the custom style prompt`() {
    val old = HomeSpeakerWire.sources(homeSpeakerV110)
    assertEquals(false, old.homeCastVoice)
    assertTrue(old.customVoices.isEmpty())
    assertEquals("", old.customStylePrompt)

    val v =
        HomeSpeakerWire.sources(
            """
        {"home_cast_voice":true,
         "gemini_voice":"clone-1",
         "announcement_style":"custom",
         "custom_style_prompt":"Speak like a pirate.",
         "custom_voices":[
           {"id":"clone-1","name":"James"},
           {"name":"no id"},
           42,
           {"id":"clone-2"}
         ]}
        """
                .trimIndent())
    assertEquals(true, v.homeCastVoice)
    assertEquals("clone-1", v.geminiVoice)
    assertEquals("custom", v.announcementStyle)
    assertEquals("Speak like a pirate.", v.customStylePrompt)
    // Entries without an id are skipped; a missing name falls back to the id.
    assertEquals(
        listOf(AgentCustomVoice("clone-1", "James"), AgentCustomVoice("clone-2", "clone-2")),
        v.customVoices)
  }

  @Test
  public fun `homespeaker reads full parity status fields, voices, homes and agent hooks`() {
    val json =
        """
      {
        "quiet_hours_active": true,
        "structure_id": "home-xyz",
        "account_email": "user@example.com",
        "has_oauth_client": true,
        "has_antigravity_tokens": true,
        "monitor_running": true,
        "last_poll_at": "2026-10-21T20:00:00Z",
        "slack_identity": "U12345",
        "active_google_chat_backend": "api",
        "chat_runtime_error": "",
        "has_slack_token": true,
        "has_beeper_token": true,
        "has_chat_access": true,
        "gws_installed": true,
        "gws_account": "user@gws.com",
        "google_chat_source": "gws",
        "poll_interval": 15,
        "legacy_launch_agent": true,
        "custom_oauth_client_id": "client-id-custom",
        "has_custom_oauth_secret": true,
        "home_speaker_version": "1.23.0",
        "recent": [
          {"id": "b-1", "text": "Turn complete", "target": "Living Room", "source": "claudeCode", "at": "2026-10-21T20:00:00Z"}
        ],
        "available_voices": [
          {"id": "v-1", "name": "Aaron", "lang": "en_US"},
          {"id": "v-2", "name": "Alex", "lang": "en_US"}
        ],
        "homes": [
          {"id": "home-xyz", "name": "Main Residence"}
        ],
        "agents": [
          {"agent": "Claude Code", "hook_state": "installed", "speaks_twice": true, "configured_by_instruction": true}
        ]
      }
    """
            .trimIndent()

    val v = HomeSpeakerWire.sources(json)
    assertEquals(true, v.quietHoursActive)
    assertEquals("home-xyz", v.structureId)
    assertEquals("user@example.com", v.accountEmail)
    assertEquals(true, v.hasOAuthClient)
    assertEquals(true, v.hasAntigravityTokens)
    assertEquals(true, v.monitorRunning)
    assertEquals("2026-10-21T20:00:00Z", v.lastPollAt)
    assertEquals("U12345", v.slackIdentity)
    assertEquals("api", v.activeGoogleChatBackend)
    assertEquals("", v.chatRuntimeError)
    assertEquals(true, v.hasSlackToken)
    assertEquals(true, v.hasBeeperToken)
    assertEquals(true, v.hasChatAccess)
    assertEquals(true, v.gwsInstalled)
    assertEquals("user@gws.com", v.gwsAccount)
    assertEquals("gws", v.googleChatSource)
    assertEquals(15, v.pollInterval)
    assertEquals(true, v.legacyLaunchAgent)
    assertEquals("client-id-custom", v.customOAuthClientId)
    assertEquals(true, v.hasCustomOAuthSecret)
    assertEquals("1.23.0", v.homeSpeakerVersion)

    assertEquals(1, v.recent.size)
    assertEquals("b-1", v.recent[0].id)
    assertEquals("Turn complete", v.recent[0].text)

    assertEquals(2, v.availableVoices.size)
    assertEquals(AgentVoice("v-1", "Aaron", "en_US"), v.availableVoices[0])

    assertEquals(1, v.homes.size)
    assertEquals(AgentHome("home-xyz", "Main Residence"), v.homes[0])

    assertEquals(1, v.agents.size)
    assertEquals(
        AgentHookStatus(
            "Claude Code", "installed", speaksTwice = true, configuredByInstruction = true),
        v.agents[0])
  }

  @Test
  public fun `agent hook status parses agent_slug and derives canonicalSlug`() {
    val json =
        """
        {
          "agents": [
            {"agent": "Claude Code", "agent_slug": "claude-code", "hook_state": "installed"},
            {"agent": "Antigravity", "hook_state": "installed", "configured_by_instruction": true},
            {"agent": "OpenCode", "agent_slug": "opencode", "hook_state": "none"},
            {"agent": "Custom Tool", "hook_state": "none"}
          ]
        }
        """
            .trimIndent()
    val v = HomeSpeakerWire.sources(json)
    assertEquals(4, v.agents.size)

    assertEquals("Claude Code", v.agents[0].agent)
    assertEquals("claude-code", v.agents[0].agentSlug)
    assertEquals("claude-code", v.agents[0].canonicalSlug)

    assertEquals("Antigravity", v.agents[1].agent)
    assertEquals("", v.agents[1].agentSlug)
    assertEquals("antigravity", v.agents[1].canonicalSlug)

    assertEquals("OpenCode", v.agents[2].agent)
    assertEquals("opencode", v.agents[2].agentSlug)
    assertEquals("opencode", v.agents[2].canonicalSlug)

    assertEquals("Custom Tool", v.agents[3].agent)
    assertEquals("", v.agents[3].agentSlug)
    assertEquals("custom-tool", v.agents[3].canonicalSlug)
  }

  @Test
  public fun `tv wire parses state and falls back cleanly on missing fields`() {
    val parsed =
        TvWire.parse(
            """
            {
              "available": true,
              "connected": true,
              "awake": true,
              "dreaming": false,
              "foreground": "SmartTube 4K",
              "mem_available_mb": 1024,
              "address": "192.168.86.42:5555"
            }
            """
                .trimIndent())
    assertEquals(
        AgentTv(
            available = true,
            connected = true,
            awake = true,
            dreaming = false,
            foreground = "SmartTube 4K",
            memAvailableMb = 1024,
            address = "192.168.86.42:5555",
            reason = "",
        ),
        parsed)

    val fallback = TvWire.parse("not json")
    assertEquals(false, fallback.available)
    assertEquals(false, fallback.connected)
    assertEquals("Standby", fallback.foreground)
    assertEquals(TvWire.DEFAULT_ADDRESS, fallback.address)
  }
}
