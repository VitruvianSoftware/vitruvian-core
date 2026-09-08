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
    // The refusal has to name the button, not the rule: this text is returned
    // to the agent verbatim and is the only instruction anyone gets.
    assertTrue((shut as BridgeDecision.Deny).reason.contains("Trust agents for 1 hour"))
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
}
