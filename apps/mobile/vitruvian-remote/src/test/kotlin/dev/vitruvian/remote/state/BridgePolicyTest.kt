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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The approval rule, the link encoding and the audit summary.
 *
 * Every one of these fails silently on a phone: a tier decided too generously runs the tool and
 * returns a perfectly good answer, a descriptor with an unescaped quote makes the Mac agent
 * announce NO tools rather than one broken one, and a summariser that keeps the whole message body
 * writes a copy of the inbox into SharedPreferences without anything looking wrong.
 */
public class BridgePolicyTest {

  private val now = 1_700_000_000_000L
  private val openWindow = now + 60_000L
  private val shutWindow = now - 1L

  // --- decide(): every branch of the table in docs/phone-bridge.md ------

  @Test
  public fun readIsAllowedWithTheWindowShut() {
    assertEquals(BridgeDecision.Allow, BridgePolicy.decide(ToolTier.Read, shutWindow, now))
  }

  @Test
  public fun readIsAllowedWithTheWindowOpen() {
    assertEquals(BridgeDecision.Allow, BridgePolicy.decide(ToolTier.Read, openWindow, now))
  }

  @Test
  public fun actNeedsTheWindow() {
    assertEquals(BridgeDecision.Allow, BridgePolicy.decide(ToolTier.Act, openWindow, now))
    val shut = BridgePolicy.decide(ToolTier.Act, shutWindow, now)
    assertTrue(shut is BridgeDecision.Deny)
    // The refusal has to name the control, not the rule: this text is returned
    // to the agent verbatim and is the only instruction anyone gets.
    val reason = (shut as BridgeDecision.Deny).reason
    assertTrue(reason.contains("Settings → Phone bridge"))
    assertTrue(reason.contains("Always"))
  }

  @Test
  public fun outboundPromptsWithoutTheWindowAndRunsWithIt() {
    assertEquals(BridgeDecision.Prompt, BridgePolicy.decide(ToolTier.Outbound, shutWindow, now))
    assertEquals(BridgeDecision.Allow, BridgePolicy.decide(ToolTier.Outbound, openWindow, now))
  }

  @Test
  public fun theWindowIsShutAtItsOwnDeadline() {
    // A window that is still open at exactly its expiry is a window that never
    // closes on a phone whose clock ticks in whole seconds.
    assertFalse(BridgePolicy.trustOpen(now, now))
    assertTrue(BridgePolicy.trustOpen(now + 1, now))
    assertEquals(BridgeDecision.Prompt, BridgePolicy.decide(ToolTier.Outbound, now, now))
  }

  @Test
  public fun neverTrustedIsShut() {
    // 0 is what an unset trust window is stored as.
    assertFalse(BridgePolicy.trustOpen(0L, now))
    assertTrue(BridgePolicy.decide(ToolTier.Act, 0L, now) is BridgeDecision.Deny)
  }

  // --- the countdown ----------------------------------------------------

  @Test
  public fun remainingTimeRoundsUpAndSaysClosedWhenItIsClosed() {
    assertEquals("closed", BridgePolicy.trustRemaining(shutWindow, now))
    assertEquals("closed", BridgePolicy.trustRemaining(now, now))
    // 30 s left must not read as "0 min": outbound tools are still unprompted.
    assertEquals("1 min left", BridgePolicy.trustRemaining(now + 30_000L, now))
    assertEquals("1 h left", BridgePolicy.trustRemaining(now + 60 * 60_000L, now))
    assertEquals("1 h 1 min left", BridgePolicy.trustRemaining(now + 61 * 60_000L, now))
  }

  @Test
  public fun trustUntilIsoIsNullWhenTheWindowIsShut() {
    assertNull(BridgePolicy.trustUntilIso(shutWindow, now))
    assertNull(BridgePolicy.trustUntilIso(0L, now))
    assertEquals("2023-11-14T22:13:20Z", BridgePolicy.trustUntilIso(now, now - 1))
  }

  @Test
  public fun trustPresetsAndAlwaysTrustBehaveWithoutOverflow() {
    assertEquals(now + 3_600_000L, BridgePolicy.trustDeadline(TrustDuration.OneHour, now))
    assertEquals(now + 28_800_000L, BridgePolicy.trustDeadline(TrustDuration.EightHours, now))
    assertEquals(BridgePolicy.TRUST_FOREVER, BridgePolicy.trustDeadline(TrustDuration.Always, now))

    assertTrue(BridgePolicy.isAlwaysTrusted(BridgePolicy.TRUST_FOREVER))
    assertFalse(BridgePolicy.isAlwaysTrusted(openWindow))
    assertFalse(BridgePolicy.isAlwaysTrusted(0L))

    assertTrue(BridgePolicy.trustOpen(BridgePolicy.TRUST_FOREVER, now))
    for (tier in ToolTier.entries) {
      assertEquals(BridgeDecision.Allow, BridgePolicy.decide(tier, BridgePolicy.TRUST_FOREVER, now))
    }
    assertEquals("always", BridgePolicy.trustRemaining(BridgePolicy.TRUST_FOREVER, now))
    assertEquals(
        "8 h left", BridgePolicy.trustRemaining(now + BridgePolicy.TRUST_WINDOW_8H_MS, now))
    assertEquals("always", BridgePolicy.trustUntilIso(BridgePolicy.TRUST_FOREVER, now))
  }

  // --- the audit summary ------------------------------------------------

  @Test
  public fun summaryKeepsTheRecipientAndClipsTheBody() {
    val body = "y".repeat(500)
    val summary = BridgePolicy.summarize(listOf("to" to "+15551234567", "body" to body))
    assertTrue(summary.startsWith("to=+15551234567"))
    assertTrue(summary.length <= BridgePolicy.SUMMARY_MAX + 1)
    // The body is capped at 40 chars BEFORE the line is capped at 80, which is
    // what keeps the number -- the part worth auditing -- on the line.
    assertFalse(summary.contains("y".repeat(BridgePolicy.TEXT_VALUE_MAX + 1)))
  }

  @Test
  public fun summaryClipsEveryTextKey() {
    val long = "z".repeat(100)
    for (key in listOf("body", "text", "message", "prompt", "BODY")) {
      val summary = BridgePolicy.summarize(listOf(key to long))
      assertFalse(
          "$key must be clipped to ${BridgePolicy.TEXT_VALUE_MAX}",
          summary.contains("z".repeat(BridgePolicy.TEXT_VALUE_MAX + 1)),
      )
    }
  }

  @Test
  public fun summaryOfNothingIsNothing() {
    assertEquals("", BridgePolicy.summarize(emptyList()))
  }

  @Test
  public fun summaryCapsTheWholeLineEvenWithoutTextKeys() {
    val summary = BridgePolicy.summarize((1..20).map { "arg$it" to "value$it" })
    assertTrue(summary.length <= BridgePolicy.SUMMARY_MAX + 1)
    assertTrue(summary.endsWith("…"))
  }

  // --- the wire encoding ------------------------------------------------

  @Test
  public fun descriptorsCarryTheRawSchemaAndTheTier() {
    val json =
        BridgePolicy.encodeDescriptors(
            listOf(
                ToolDescriptor(
                    name = "sms.list",
                    description = "Reads texts. ${BridgePolicy.UNTRUSTED}",
                    inputSchema =
                        "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"integer\"}}}",
                    tier = ToolTier.Read,
                )))
    val decoded = JsonReader(json).readValue() as List<*>
    val tool = decoded.single() as Map<*, *>
    assertEquals("sms.list", tool["name"])
    assertEquals("read", tool["tier"])
    // The schema survives as an OBJECT, not as a string: a schema that arrives
    // quoted makes tools/list valid JSON that no MCP client can use.
    val schema = tool["inputSchema"] as Map<*, *>
    assertTrue((schema["properties"] as Map<*, *>).containsKey("n"))
  }

  @Test
  public fun aBlankSchemaBecomesAnEmptyObjectSchema() {
    val json =
        BridgePolicy.encodeDescriptors(
            listOf(ToolDescriptor("phone.status", "d", "", ToolTier.Read)))
    val tool = (JsonReader(json).readValue() as List<*>).single() as Map<*, *>
    assertEquals("object", (tool["inputSchema"] as Map<*, *>)["type"])
  }

  @Test
  public fun quotesAndNewlinesInADescriptionDoNotBreakTheDocument() {
    val json =
        BridgePolicy.encodeDescriptors(
            listOf(
                ToolDescriptor(
                    "apps.open",
                    "Opens \"an app\".\nSecond line\twith a tab.",
                    BridgePolicy.EMPTY_SCHEMA,
                    ToolTier.Act,
                )))
    val tool = (JsonReader(json).readValue() as List<*>).single() as Map<*, *>
    assertEquals("Opens \"an app\".\nSecond line\twith a tab.", tool["description"])
    assertEquals("act", tool["tier"])
  }

  @Test
  public fun linkBodyCarriesTheDeviceAndTheTools() {
    val body =
        BridgePolicy.encodeLinkBody(
            "Pixel Fold",
            "16",
            listOf(ToolDescriptor("sms.send", "d", BridgePolicy.EMPTY_SCHEMA, ToolTier.Outbound)),
        )
    val o = JsonReader(body).readValue() as Map<*, *>
    val device = o["device"] as Map<*, *>
    assertEquals("Pixel Fold", device["model"])
    assertEquals("16", device["android"])
    assertEquals("outbound", ((o["tools"] as List<*>).single() as Map<*, *>)["tier"])
  }

  @Test
  public fun linkBodyCarriesTheAppVersionWhenKnown() {
    val body = BridgePolicy.encodeLinkBody("Pixel Fold", "16", emptyList(), appVersion = "0.1.48")
    val device = (JsonReader(body).readValue() as Map<*, *>)["device"] as Map<*, *>
    assertEquals("0.1.48", device["app_version"])
  }

  @Test
  public fun linkBodyLeavesOutAnUnknownAppVersion() {
    val body = BridgePolicy.encodeLinkBody("Pixel Fold", "16", emptyList(), appVersion = "")
    val device = (JsonReader(body).readValue() as Map<*, *>)["device"] as Map<*, *>
    assertEquals(false, device.containsKey("app_version"))
  }

  @Test
  public fun resultCarriesOneTextItemAndTheErrorFlag() {
    val body = JsonReader(BridgePolicy.encodeResult("c-17", "{\"ok\":true}", false))
    val o = body.readValue() as Map<*, *>
    assertEquals("c-17", o["id"])
    assertEquals(false, o["is_error"])
    val item = (o["content"] as List<*>).single() as Map<*, *>
    assertEquals("text", item["type"])
    // The tool's own JSON is the TEXT of the item, not a nested document.
    assertEquals("{\"ok\":true}", item["text"])
  }

  @Test
  public fun anErrorResultSaysSo() {
    val o = JsonReader(BridgePolicy.encodeResult("c-1", BridgePolicy.NO_ANSWER, true)).readValue()
    assertEquals(true, (o as Map<*, *>)["is_error"])
  }

  // --- a result with a picture in it ------------------------------------

  @Test
  public fun aScreenshotResultCarriesTheTextAndTheImage() {
    val body =
        JsonReader(BridgePolicy.encodeResult("c-9", "{\"width\":800}", false, "AAECAw=="))
            .readValue() as Map<*, *>
    val content = body["content"] as List<*>
    // Two items, and the TEXT one first: it is where the pixel size is, and an
    // agent that reads the picture without it taps where things are in the
    // picture rather than on the phone.
    assertEquals(2, content.size)
    assertEquals("text", (content[0] as Map<*, *>)["type"])
    val image = content[1] as Map<*, *>
    assertEquals("image", image["type"])
    assertEquals("AAECAw==", image["data"])
    assertEquals("image/jpeg", image["mimeType"])
  }

  @Test
  public fun aResultWithNoPictureHasNoImageItem() {
    // The regression this pins: an image item with an empty `data` is valid
    // JSON, reaches the Mac, and renders as a broken picture beside every
    // answer the phone ever gives.
    val body =
        JsonReader(BridgePolicy.encodeResult("c-9", "hi", false, "")).readValue() as Map<*, *>
    assertEquals(1, (body["content"] as List<*>).size)
  }

  @Test
  public fun theImageItemEscapesWhatItIsGiven() {
    val item = JsonReader(BridgePolicy.encodeImageContent("a\"b", "image/png")).readValue()
    assertEquals("a\"b", (item as Map<*, *>)["data"])
    assertEquals("image/png", item["mimeType"])
  }

  // --- the screen tools' rules ------------------------------------------

  @Test
  public fun theScreenshotWidthIsClampedRatherThanRefused() {
    assertEquals(ScreenPolicy.DEFAULT_WIDTH, ScreenPolicy.clampWidth(0))
    assertEquals(ScreenPolicy.DEFAULT_WIDTH, ScreenPolicy.clampWidth(-1))
    assertEquals(ScreenPolicy.MIN_WIDTH, ScreenPolicy.clampWidth(1))
    assertEquals(ScreenPolicy.MAX_WIDTH, ScreenPolicy.clampWidth(99_999))
    assertEquals(1000, ScreenPolicy.clampWidth(1000))
  }

  @Test
  public fun keyNamesParseAndUnknownOnesDoNot() {
    assertEquals(ScreenKey.Back, ScreenPolicy.key("back"))
    assertEquals(ScreenKey.QuickSettings, ScreenPolicy.key("  Quick-Settings "))
    assertEquals(ScreenKey.QuickSettings, ScreenPolicy.key("quick settings"))
    // Null, not a default: a key name that silently fell back to "back" would
    // press the wrong thing and report success.
    assertNull(ScreenPolicy.key("power"))
    assertNull(ScreenPolicy.key(""))
  }

  @Test
  public fun boundsRoundTripAndAMalformedOneIsNull() {
    val text = ScreenPolicy.bounds(12, 100, 312, 200)
    assertEquals("12,100,312,200", text)
    assertTrue(ScreenPolicy.parseBounds(text)!!.contentEquals(intArrayOf(12, 100, 312, 200)))
    assertTrue(ScreenPolicy.centre(text)!!.contentEquals(intArrayOf(162, 150)))
    // Each of these would otherwise become a tap at 0,0 -- the status bar.
    assertNull(ScreenPolicy.parseBounds("12,100,312"))
    assertNull(ScreenPolicy.parseBounds("12,100,312,200,4"))
    assertNull(ScreenPolicy.parseBounds("12,100,312,x"))
    assertNull(ScreenPolicy.centre(""))
  }

  @Test
  public fun rolesAndViewIdsLoseTheirPackage() {
    assertEquals("TextView", ScreenPolicy.shortRole("android.widget.TextView"))
    assertEquals("node", ScreenPolicy.shortRole(null))
    assertEquals("node", ScreenPolicy.shortRole(""))
    assertEquals("send", ScreenPolicy.shortViewId("dev.vitruvian.remote:id/send"))
    assertEquals("", ScreenPolicy.shortViewId(null))
  }

  @Test
  public fun theTreeIsIndentedByDepthAndCarriesEveryHandle() {
    val text =
        ScreenPolicy.formatTree(
            packageName = "com.example.mail",
            window = "Inbox",
            nodes =
                listOf(
                    ScreenNode(0, "FrameLayout", desc = "Inbox"),
                    ScreenNode(
                        depth = 2,
                        role = "Button",
                        text = "Send",
                        viewId = "send",
                        bounds = "12,100,312,200",
                        flags = listOf("clickable", "focused"),
                    ),
                ),
        )
    val lines = text.lines()
    assertEquals("package=com.example.mail window=\"Inbox\" nodes=2", lines[0])
    assertEquals("FrameLayout (Inbox)", lines[1])
    // Four spaces: depth 2. The indentation is the only thing that says what
    // contains what, and a flat tree reads as a flat screen.
    assertEquals("    Button \"Send\" #send [12,100,312,200] clickable focused", lines[2])
  }

  @Test
  public fun aNodesTextNeverBreaksTheLine() {
    // A label with a newline in it would put the next node's line at this
    // node's indentation, which is indistinguishable from real structure.
    val text =
        ScreenPolicy.formatTree("a", "", listOf(ScreenNode(0, "TextView", text = "one\ntwo")))
    assertEquals(2, text.lines().size)
    assertTrue(text.endsWith("TextView \"one two\""))
  }

  @Test
  public fun aTruncatedTreeSaysSo() {
    val nodes = listOf(ScreenNode(0, "TextView", text = "x"))
    assertFalse(ScreenPolicy.formatTree("a", "", nodes).contains("stopped at"))
    // Silence here is the bug: an agent handed the first 400 nodes of a
    // thousand concludes the button it wanted is not on the screen.
    val cut = ScreenPolicy.formatTree("a", "", nodes, truncated = true)
    assertTrue(cut.contains("stopped at ${ScreenPolicy.MAX_NODES} nodes"))
  }

  // --- the stored audit trail -------------------------------------------

  @Test
  public fun theAuditTrailSurvivesARoundTrip() {
    val entries =
        listOf(
            BridgeAuditEntry(now, "sms.send", "to=+1555 body=hi", "sent", "approved"),
            BridgeAuditEntry(now - 1, "sms.list", "n=5", "5 messages", "read tier"),
        )
    assertEquals(entries, BridgePolicy.decodeAudit(BridgePolicy.encodeAudit(entries)))
  }

  @Test
  public fun theAuditTrailIsCappedAtAHundred() {
    val many = (1..150).map { BridgeAuditEntry(now, "phone.status", "", "ok", "read tier") }
    assertEquals(
        BridgePolicy.AUDIT_LIMIT, BridgePolicy.decodeAudit(BridgePolicy.encodeAudit(many)).size)
  }

  @Test
  public fun garbageDecodesToAnEmptyTrailRatherThanThrowing() {
    assertEquals(emptyList<BridgeAuditEntry>(), BridgePolicy.decodeAudit(""))
    assertEquals(emptyList<BridgeAuditEntry>(), BridgePolicy.decodeAudit("not json"))
    assertEquals(emptyList<BridgeAuditEntry>(), BridgePolicy.decodeAudit("{\"a\":1}"))
    // A row with no tool name is dropped, and the rest of the trail survives.
    assertEquals(1, BridgePolicy.decodeAudit("[{\"tool\":\"\"},{\"tool\":\"calls.log\"}]").size)
  }

  // --- phone.speak WAV pre-roll silence and duration-scaled timeouts ---

  private fun makePcmWav(
      sampleRate: Int,
      channels: Int,
      bitsPerSample: Int,
      pcmPayload: ByteArray,
      declaredDataSize: Long? = null,
  ): ByteArray {
    val blockAlign = channels * bitsPerSample / 8
    val byteRate = sampleRate * blockAlign
    val dataSize = declaredDataSize ?: pcmPayload.size.toLong()
    val riffSize = 36L + pcmPayload.size.toLong()
    val header = ByteArray(44)
    fun putAscii(off: Int, s: String) {
      for (k in s.indices) header[off + k] = s[k].code.toByte()
    }
    fun putU16(off: Int, v: Int) {
      header[off] = (v and 0xFF).toByte()
      header[off + 1] = ((v ushr 8) and 0xFF).toByte()
    }
    fun putU32(off: Int, v: Long) {
      header[off] = (v and 0xFFL).toByte()
      header[off + 1] = ((v ushr 8) and 0xFFL).toByte()
      header[off + 2] = ((v ushr 16) and 0xFFL).toByte()
      header[off + 3] = ((v ushr 24) and 0xFFL).toByte()
    }
    putAscii(0, "RIFF")
    putU32(4, riffSize)
    putAscii(8, "WAVE")
    putAscii(12, "fmt ")
    putU32(16, 16L)
    putU16(20, 1) // PCM
    putU16(22, channels)
    putU32(24, sampleRate.toLong())
    putU32(28, byteRate.toLong())
    putU16(32, blockAlign)
    putU16(34, bitsPerSample)
    putAscii(36, "data")
    putU32(40, dataSize)
    return header + pcmPayload
  }

  @Test
  public fun wavDurationAndPrerollSilenceFor24KhzMonoPcm() {
    val originalPayload = ByteArray(48_000) { 0x42 } // 1.0 s at 24 kHz 16-bit mono
    val wav = makePcmWav(24_000, 1, 16, originalPayload)
    assertEquals(1.0, BridgePolicy.wavDurationSeconds(wav)!!, 0.0001)

    val padded = BridgePolicy.prependWavSilence(wav, 300)
    // 300 ms at 48,000 bytes/s = 14,400 zero bytes inserted at byte 44.
    assertEquals(wav.size + 14_400, padded.size)
    assertEquals(1.3, BridgePolicy.wavDurationSeconds(padded)!!, 0.0001)
    for (i in 44 until 44 + 14_400) {
      assertEquals("pre-roll sample at $i must be silence", 0.toByte(), padded[i])
    }
    for (i in 0 until originalPayload.size) {
      assertEquals(originalPayload[i], padded[44 + 14_400 + i])
    }
  }

  @Test
  public fun wavDurationHandlesStreamedSizesAndRejectsNonWav() {
    val payload = ByteArray(24_000) { 1 } // 0.5 s at 48,000 bytes/s
    val streamed = makePcmWav(24_000, 1, 16, payload, declaredDataSize = 0xFFFFFFFFL)
    assertEquals(0.5, BridgePolicy.wavDurationSeconds(streamed)!!, 0.0001)

    val paddedStreamed = BridgePolicy.prependWavSilence(streamed, 300)
    assertEquals(streamed.size + 14_400, paddedStreamed.size)
    assertEquals(0.8, BridgePolicy.wavDurationSeconds(paddedStreamed)!!, 0.0001)

    val garbage = "not-a-wav-file-at-all".toByteArray()
    assertNull(BridgePolicy.wavDurationSeconds(garbage))
    assertTrue(garbage.contentEquals(BridgePolicy.prependWavSilence(garbage, 300)))
  }

  @Test
  public fun speakTimeoutScalesWithAudioAndTextDurationAndClamps() {
    assertEquals(45L, BridgePolicy.speakTimeoutSeconds(10.0, textLength = 0))
    assertEquals(109L, BridgePolicy.speakTimeoutSeconds(78.1, textLength = 0))
    assertEquals(180L, BridgePolicy.speakTimeoutSeconds(300.0, textLength = 0))

    assertEquals(45L, BridgePolicy.speakTimeoutSeconds(null, textLength = 50))
    assertEquals(180L, BridgePolicy.speakTimeoutSeconds(null, textLength = 1500))
  }

  @Test
  public fun selectMlKitVoicePrefersReadyVoiceAndFallsBackCleanly() {
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Unavailable,
        BridgePolicy.selectMlKitVoice(emptyList()),
    )

    val downloadableOnly =
        listOf(
            BridgePolicy.MlKitVoiceCandidate(
                "star02", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
            BridgePolicy.MlKitVoiceCandidate(
                "star05", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
        )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.NeedsDownload("star02"),
        BridgePolicy.selectMlKitVoice(downloadableOnly),
    )

    val mixed =
        listOf(
            BridgePolicy.MlKitVoiceCandidate(
                "star02", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
            BridgePolicy.MlKitVoiceCandidate(
                "star05", "en-US", BridgePolicy.MlKitVoiceStatus.Available),
        )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Ready("star05"),
        BridgePolicy.selectMlKitVoice(mixed),
    )

    // A picked voice that is not downloaded yet never blocks: a ready voice speaks meanwhile.
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Ready("star05"),
        BridgePolicy.selectMlKitVoice(mixed, preferredName = "STAR02"),
    )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Ready("star05"),
        BridgePolicy.selectMlKitVoice(mixed, preferredName = "star05"),
    )
    // Missing preferred voice falls back to the first already-available voice.
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Ready("star05"),
        BridgePolicy.selectMlKitVoice(mixed, preferredName = "nonexistent"),
    )

    // When a voice is already downloading and none are ready, do not start a second download.
    val downloading =
        listOf(
            BridgePolicy.MlKitVoiceCandidate(
                "star02", "en-US", BridgePolicy.MlKitVoiceStatus.Downloading),
            BridgePolicy.MlKitVoiceCandidate(
                "star05", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
        )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Unavailable,
        BridgePolicy.selectMlKitVoice(downloading),
    )
  }

  @Test
  public fun mlKitNeverFallsBackOnceAudioHasStarted() {
    val ends = BridgePolicy.MlKitEnd.values().filter { it != BridgePolicy.MlKitEnd.Done }
    for (end in ends) {
      val outcome = BridgePolicy.classifyMlKitEnd(end, started = true, unplugged = false)
      assertTrue(
          "$end after audio started must not fall back",
          outcome is BridgePolicy.MlKitOutcome.Partial)
    }
  }

  @Test
  public fun mlKitFallsBackOnlyWhenNothingWasHeard() {
    for (end in BridgePolicy.MlKitEnd.values().filter { it != BridgePolicy.MlKitEnd.Done }) {
      assertTrue(
          BridgePolicy.classifyMlKitEnd(end, started = false, unplugged = false)
              is BridgePolicy.MlKitOutcome.Fallback)
    }
    assertEquals(
        BridgePolicy.MlKitOutcome.Fallback("ML Kit TTS did not start"),
        BridgePolicy.classifyMlKitEnd(BridgePolicy.MlKitEnd.StartTimeout, false, false))
  }

  @Test
  public fun mlKitStopIsNotReportedAsTimeout() {
    val outcome = BridgePolicy.classifyMlKitEnd(BridgePolicy.MlKitEnd.Stopped, true, false)
    assertEquals(BridgePolicy.MlKitOutcome.Partial("ML Kit TTS stopped partway through"), outcome)
  }

  @Test
  public fun mlKitDoneIsSpokenAndUnplugWins() {
    // Done counts as spoken even without a start signal: falling back could repeat it.
    assertEquals(
        BridgePolicy.MlKitOutcome.Spoken,
        BridgePolicy.classifyMlKitEnd(
            BridgePolicy.MlKitEnd.Done, started = false, unplugged = false))
    for (end in BridgePolicy.MlKitEnd.values()) {
      assertEquals(
          BridgePolicy.MlKitOutcome.Unplugged,
          BridgePolicy.classifyMlKitEnd(end, started = true, unplugged = true))
    }
  }

  @Test
  public fun fallbackStaysInsideOneBudget() {
    val text = 300 // about 30 s of speech
    val budget = BridgePolicy.speakTimeoutSeconds(null, text)
    // A quick ML Kit failure leaves the Android voice the rest of the same budget.
    assertEquals(budget - 2, BridgePolicy.fallbackTimeoutSeconds(budget, 2, text))
    // ML Kit used most of the budget: too little left to say it, so report failure on time.
    assertNull(BridgePolicy.fallbackTimeoutSeconds(budget, budget - 10, text))
    assertNull(BridgePolicy.fallbackTimeoutSeconds(budget, budget + 5, text))
    // The fallback never gets more than what was left of the one budget.
    for (elapsed in 0L..budget) {
      val left = BridgePolicy.fallbackTimeoutSeconds(budget, elapsed, text) ?: continue
      assertTrue(elapsed + left <= budget)
    }
  }

  @Test
  public fun phoneBudgetStaysUnderTheMacWait() {
    // The Mac waits speech + 45 s, clamped to 60–210 s (speaker.rs phone_say_timeout).
    // The phone's whole budget, fallback included, must end before that.
    for (len in listOf(1, 50, 400, 1500, 5000)) {
      val speech = maxOf(1L, len / 10L)
      val macWait = (speech + 45L).coerceIn(60L, 210L)
      assertTrue(BridgePolicy.speakTimeoutSeconds(null, len) < macWait)
    }
  }

  @Test
  public fun voiceDownloadsOnlyOnUnmeteredNetworks() {
    val needs = BridgePolicy.MlKitVoiceSelection.NeedsDownload("star02")
    assertTrue(
        BridgePolicy.shouldDownloadMlKitVoice(needs, unmetered = true, downloadInFlight = false))
    assertFalse(
        BridgePolicy.shouldDownloadMlKitVoice(needs, unmetered = false, downloadInFlight = false))
    assertFalse(
        BridgePolicy.shouldDownloadMlKitVoice(needs, unmetered = true, downloadInFlight = true))
    assertFalse(
        BridgePolicy.shouldDownloadMlKitVoice(
            BridgePolicy.MlKitVoiceSelection.Ready("star02"),
            unmetered = true,
            downloadInFlight = false))
  }

  @Test
  public fun voiceCacheExpiresSoonerWhenNothingIsReady() {
    assertTrue(BridgePolicy.mlKitVoiceCacheFresh(0, ready = true))
    assertTrue(
        BridgePolicy.mlKitVoiceCacheFresh(BridgePolicy.MLKIT_NOT_READY_CACHE_MS, ready = true))
    assertFalse(
        BridgePolicy.mlKitVoiceCacheFresh(BridgePolicy.MLKIT_NOT_READY_CACHE_MS, ready = false))
    assertFalse(BridgePolicy.mlKitVoiceCacheFresh(BridgePolicy.MLKIT_READY_CACHE_MS, ready = true))
    // A clock that went backwards never counts as fresh.
    assertFalse(BridgePolicy.mlKitVoiceCacheFresh(-1, ready = true))
  }

  private fun voice(name: String, status: BridgePolicy.MlKitVoiceStatus, gender: String = "") =
      PhoneVoiceOption(name, "en-US", gender, status)

  @Test
  public fun pickedVoiceSpeaksWhenReadyCaseInsensitive() {
    val voices =
        listOf(
            BridgePolicy.MlKitVoiceCandidate(
                "star02", "en-US", BridgePolicy.MlKitVoiceStatus.Available),
            BridgePolicy.MlKitVoiceCandidate(
                "star05", "en-US", BridgePolicy.MlKitVoiceStatus.Available),
        )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Ready("star05"),
        BridgePolicy.selectMlKitVoice(voices, preferredName = "STAR05"))
    // Automatic (blank) takes the first ready voice.
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Ready("star02"),
        BridgePolicy.selectMlKitVoice(voices, preferredName = "  "))
  }

  @Test
  public fun pickerListsReadyVoicesFirst() {
    val sorted =
        BridgePolicy.sortVoicesForPicker(
            listOf(
                voice("zeta", BridgePolicy.MlKitVoiceStatus.Downloadable),
                voice("Beta", BridgePolicy.MlKitVoiceStatus.Unavailable),
                voice("alpha", BridgePolicy.MlKitVoiceStatus.Downloadable),
                voice("omega", BridgePolicy.MlKitVoiceStatus.Available),
                voice("mid", BridgePolicy.MlKitVoiceStatus.Downloading),
            ))
    assertEquals(listOf("omega", "mid", "alpha", "zeta", "Beta"), sorted.map { it.name })
  }

  @Test
  public fun voiceInUseFollowsTheSavedPickOnlyWhenItCanSpeak() {
    val voices =
        listOf(
            voice("star02", BridgePolicy.MlKitVoiceStatus.Available),
            voice("star05", BridgePolicy.MlKitVoiceStatus.Downloading),
        )
    assertEquals("star02", BridgePolicy.voiceInUse(voices, saved = ""))
    assertEquals("star02", BridgePolicy.voiceInUse(voices, saved = "star05"))
    assertEquals("star02", BridgePolicy.voiceInUse(voices, saved = "gone"))
    assertNull(
        BridgePolicy.voiceInUse(listOf(voice("x", BridgePolicy.MlKitVoiceStatus.Downloadable)), ""))
  }

  @Test
  public fun voiceSubtitleSaysGenderAndStatusAndLanguageOnlyWhenMixed() {
    assertEquals(
        "female · on this phone",
        BridgePolicy.voiceSubtitle(voice("a", BridgePolicy.MlKitVoiceStatus.Available, "female")))
    assertEquals(
        "English (United States) · download to use",
        BridgePolicy.voiceSubtitle(
            voice("a", BridgePolicy.MlKitVoiceStatus.Downloadable),
            showLanguage = true,
            displayLocale = java.util.Locale.US,
        ))
    assertFalse(
        BridgePolicy.voicesMixLanguages(
            listOf(voice("a", BridgePolicy.MlKitVoiceStatus.Available))))
    assertTrue(
        BridgePolicy.voicesMixLanguages(
            listOf(
                voice("a", BridgePolicy.MlKitVoiceStatus.Available),
                PhoneVoiceOption("b", "en-GB", "", BridgePolicy.MlKitVoiceStatus.Available))))
  }

  @Test
  public fun voiceTitleIsReadable() {
    // The ids this Pixel actually reported.
    assertEquals("Star 02", BridgePolicy.voiceTitle("en-us-x-star02"))
    assertEquals("Star 05", BridgePolicy.voiceTitle("en-us-x-star05-local"))
    assertEquals("Orus", BridgePolicy.voiceTitle("Orus"))
    assertEquals("weird-name", BridgePolicy.voiceTitle("weird-name"))
  }

  @Test
  public fun pickedVoiceIsTheOneFetchedWhenNothingIsReady() {
    val none =
        listOf(
            BridgePolicy.MlKitVoiceCandidate(
                "star02", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
            BridgePolicy.MlKitVoiceCandidate(
                "star05", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
        )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.NeedsDownload("star05"),
        BridgePolicy.selectMlKitVoice(none, preferredName = "star05"))
    // The pick is already downloading and nothing is ready: do not start another download.
    val pickDownloading =
        listOf(
            BridgePolicy.MlKitVoiceCandidate(
                "star02", "en-US", BridgePolicy.MlKitVoiceStatus.Downloadable),
            BridgePolicy.MlKitVoiceCandidate(
                "star05", "en-US", BridgePolicy.MlKitVoiceStatus.Downloading),
        )
    assertEquals(
        BridgePolicy.MlKitVoiceSelection.Unavailable,
        BridgePolicy.selectMlKitVoice(pickDownloading, preferredName = "star05"))
  }

  @Test
  public fun getIsNeverDroppedForAnotherVoicesDownload() {
    // An automatic download of star02 is running; Get on star05 still starts.
    assertTrue(BridgePolicy.pickerShouldStartDownload("star05", setOf("star02")))
    assertFalse(BridgePolicy.pickerShouldStartDownload("star05", setOf("star05")))
    assertFalse(BridgePolicy.pickerShouldStartDownload(" ", emptySet()))
    // While our download runs, the list says downloading even if the engine still says
    // downloadable, so Get does not come back mid-download.
    assertEquals(
        BridgePolicy.MlKitVoiceStatus.Downloading,
        BridgePolicy.statusWithInFlight(
            BridgePolicy.MlKitVoiceStatus.Downloadable, "star05", setOf("star05")))
    assertEquals(
        BridgePolicy.MlKitVoiceStatus.Downloadable,
        BridgePolicy.statusWithInFlight(
            BridgePolicy.MlKitVoiceStatus.Downloadable, "star02", setOf("star05")))
    assertEquals(
        BridgePolicy.MlKitVoiceStatus.Available,
        BridgePolicy.statusWithInFlight(
            BridgePolicy.MlKitVoiceStatus.Available, "star05", setOf("star05")))
  }

  @Test
  public fun aUseDuringALookupIsNotOverwrittenByTheOldAnswer() {
    val gate = GenerationGate()
    val lookup = gate.begin()
    assertTrue(gate.stillCurrent(lookup))
    gate.invalidate() // the user tapped Use while the lookup was running
    assertFalse("stale lookup must not fill the cache", gate.stillCurrent(lookup))
    assertTrue(gate.stillCurrent(gate.begin()))
  }

  @Test
  public fun finishWindowCountsFromTheRealStart() {
    // A 15 s sample budget that started after 0.7 s keeps 14.3 s, not 15 - 10 = 5 s (the bug
    // seen on the phone cut a sample at 2 s with a 12 s budget).
    assertEquals(14_300L, BridgePolicy.mlKitFinishWindowMs(15, 700))
    assertEquals(0L, BridgePolicy.mlKitFinishWindowMs(15, 20_000))
    assertEquals(15_000L, BridgePolicy.mlKitFinishWindowMs(15, -5))
  }

  @Test
  public fun retriesOnceOnAFreshClientAfterAnEngineError() {
    // Seen on a Pixel after Google's speech app updated: every call failed at once with
    // "not bound to TTS engine" until the client was rebuilt.
    val budget = BridgePolicy.speakTimeoutSeconds(null, 100)
    assertTrue(BridgePolicy.retryMlKitWithFreshClient(true, true, 0, budget - 1, 100))
    // Only once.
    assertFalse(BridgePolicy.retryMlKitWithFreshClient(true, true, 1, budget - 1, 100))
    // Not when a new client cannot help (no voice ready, slow start).
    assertFalse(BridgePolicy.retryMlKitWithFreshClient(true, false, 0, budget - 1, 100))
    // Never once audio was heard, or the announcement would repeat.
    assertFalse(BridgePolicy.retryMlKitWithFreshClient(false, true, 0, budget - 1, 100))
    // Not when the budget left could not cover a retry and the Android voice after it.
    assertFalse(BridgePolicy.retryMlKitWithFreshClient(true, true, 0, 20, 100))
  }

  private data class FakeAttempt(val failedBeforeAudio: Boolean, val freshHelps: Boolean)

  private fun runRetry(
      results: List<FakeAttempt>,
      elapsed: Long,
      budget: Long = 60,
      textLength: Int = 100,
  ): Pair<List<Long>, FakeAttempt> {
    val budgets = mutableListOf<Long>()
    val out =
        BridgePolicy.speakWithFreshClientRetry(
            budgetSeconds = budget,
            textLength = textLength,
            elapsedSeconds = { elapsed },
            describe = { a: FakeAttempt ->
              BridgePolicy.MlKitAttempt(a.failedBeforeAudio, a.freshHelps)
            },
        ) { remaining ->
          budgets += remaining
          results[budgets.size - 1]
        }
    return budgets to out
  }

  @Test
  public fun aDeadClientIsRetriedOnceWithTheBudgetLeft() {
    val dead = FakeAttempt(failedBeforeAudio = true, freshHelps = true)
    val spoke = FakeAttempt(failedBeforeAudio = false, freshHelps = false)
    val (budgets, out) = runRetry(listOf(dead, spoke), elapsed = 2)
    assertEquals(listOf(60L, 58L), budgets)
    assertEquals(spoke, out)
  }

  @Test
  public fun noRetryWhenAudioWasHeardOrAFreshClientCannotHelp() {
    // Something was heard (mid-sentence failure): a retry would repeat the start.
    val heard = FakeAttempt(failedBeforeAudio = false, freshHelps = true)
    assertEquals(listOf(60L), runRetry(listOf(heard), elapsed = 2).first)
    // No voice ready: a new client would not change that.
    val notReady = FakeAttempt(failedBeforeAudio = true, freshHelps = false)
    assertEquals(listOf(60L), runRetry(listOf(notReady), elapsed = 2).first)
    // Twice dead: still only one retry.
    val dead = FakeAttempt(failedBeforeAudio = true, freshHelps = true)
    val (budgets, out) = runRetry(listOf(dead, dead, dead), elapsed = 2)
    assertEquals(2, budgets.size)
    assertEquals(dead, out)
    // Too little budget left for a retry plus the Android voice.
    assertEquals(listOf(60L), runRetry(listOf(dead), elapsed = 40).first)
  }

  @Test
  public fun aNewClientTellsALostEngineFromAPhoneWithNoVoices() {
    // Voices listed: no probe needed, never stale.
    assertFalse(BridgePolicy.needsStaleProbe(8))
    assertFalse(BridgePolicy.sharedClientIsStale(8, probeCount = 8))
    // Empty or no answer from ours, a new client sees voices: ours lost its engine. This covers
    // a client made by the picker that never looked up voices before the engine restarted.
    assertTrue(BridgePolicy.sharedClientIsStale(0, probeCount = 8))
    assertTrue(BridgePolicy.sharedClientIsStale(BridgePolicy.VOICES_NO_ANSWER, probeCount = 8))
    // The new client sees none either: a phone with no voices, or an engine that never answers.
    // Not stale, so the answer is cached instead of rebuilding on every announcement.
    assertFalse(BridgePolicy.sharedClientIsStale(0, probeCount = 0))
    assertFalse(
        BridgePolicy.sharedClientIsStale(
            BridgePolicy.VOICES_NO_ANSWER, BridgePolicy.VOICES_NO_ANSWER))
  }

  @Test
  public fun aThrowAfterAudioStartedIsReportedNotRetried() {
    assertEquals(
        BridgePolicy.AfterThrow.ReportPartial, BridgePolicy.afterClientThrow(started = true))
    assertEquals(
        BridgePolicy.AfterThrow.RetryOrFallBack, BridgePolicy.afterClientThrow(started = false))
  }

  @Test
  public fun attemptMappingOnlyRetriesFallbackableErrors() {
    // A partial result is not an error: never "failed before audio", never retried.
    val partial =
        BridgePolicy.mlKitAttemptOf(
            isError = false, allowFallback = false, freshClientMayHelp = true)
    assertFalse(partial.failedBeforeAudio)
    assertFalse(partial.freshClientMayHelp)
    // An error the Android voice must not take over (e.g. headphones unplugged): no retry.
    assertFalse(
        BridgePolicy.mlKitAttemptOf(true, allowFallback = false, freshClientMayHelp = true)
            .failedBeforeAudio)
    assertEquals(
        BridgePolicy.MlKitAttempt(failedBeforeAudio = true, freshClientMayHelp = true),
        BridgePolicy.mlKitAttemptOf(
            isError = true, allowFallback = true, freshClientMayHelp = true))
  }
}
