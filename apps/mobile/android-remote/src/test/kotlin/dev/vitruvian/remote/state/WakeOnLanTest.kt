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

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins the magic packet's bytes.
 *
 * Same reasoning as `HidCodesTest`: this is a fire-and-forget datagram nothing ever acknowledges. A
 * packet with the address bytes in the wrong order, or fifteen repetitions instead of sixteen, is
 * sent successfully, is carried by the network, and wakes nothing at all -- there is no error, no
 * log line and no reply for anything downstream to notice. The bytes ARE the behaviour, so they are
 * asserted literally rather than re-derived from the constants that would be wrong.
 */
class WakeOnLanTest {

  private val mac = "a4:83:e7:1c:0b:2f"
  private val expected = byteArrayOf(0xA4.toByte(), 0x83.toByte(), 0xE7.toByte(), 0x1C, 0x0B, 0x2F)

  @Test
  fun `packet is six sync bytes then the address sixteen times`() {
    val packet = WakeOnLan.packetFor(mac)!!

    assertEquals("6 + 16 x 6", 102, packet.size)
    assertEquals("the declared size must match the built one", WakeOnLan.PACKET_BYTES, packet.size)
    for (i in 0 until 6) {
      assertEquals("sync byte $i is 0xFF", 0xFF.toByte(), packet[i])
    }
    for (repeat in 0 until 16) {
      val offset = 6 + repeat * 6
      assertArrayEquals(
          "repetition $repeat carries the address in wire order",
          expected,
          packet.copyOfRange(offset, offset + 6),
      )
    }
  }

  @Test
  fun `the address keeps its byte order`() {
    // Reversed bytes would still produce a 102-byte packet that sends
    // cleanly and wakes a machine that does not exist. Asserted against a
    // literal rather than against parseMac's own output.
    assertArrayEquals(expected, WakeOnLan.parseMac(mac))
  }

  @Test
  fun `separators are cosmetic`() {
    assertArrayEquals(expected, WakeOnLan.parseMac("A4-83-E7-1C-0B-2F"))
    assertArrayEquals(expected, WakeOnLan.parseMac("a483e71c0b2f"))
    assertArrayEquals(expected, WakeOnLan.parseMac(" a4:83:E7:1c:0b:2F "))
  }

  @Test
  fun `an address that is not one gives null rather than a short packet`() {
    // The address arrives from the agent over the network, so this is an
    // ordinary condition the caller reports -- not a crash, and above all not
    // a truncated packet sent anyway.
    assertNull(WakeOnLan.parseMac(""))
    assertNull(WakeOnLan.parseMac("a4:83:e7:1c:0b"))
    assertNull(WakeOnLan.parseMac("a4:83:e7:1c:0b:2f:99"))
    assertNull(WakeOnLan.parseMac("not a mac address"))
    assertNull(WakeOnLan.packetFor("nope"))
  }

  @Test
  fun `the port is UDP discard`() {
    assertEquals(9, WakeOnLan.PORT)
  }
}
