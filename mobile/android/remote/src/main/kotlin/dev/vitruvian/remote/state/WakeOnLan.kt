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
 * The Wake-on-LAN magic packet.
 *
 * Split out of the state holder, and free of every Android import, for the same reason as
 * `HidCodes`: this is a wire format that fails SILENTLY. A packet with the address bytes in the
 * wrong order, or one repetition short, is sent successfully, is accepted by the network, and wakes
 * nothing at all -- there is no error anywhere for a test to catch except the bytes themselves.
 *
 * The format is AMD's, unchanged since 1995: six 0xFF bytes, then the target's six-byte MAC
 * repeated sixteen times, 102 bytes in total, sent as a UDP broadcast to port 9.
 */
public object WakeOnLan {

  /** UDP discard. The packet is never read by anything; the NIC matches on its contents. */
  public const val PORT: Int = 9

  private const val HEADER_BYTES = 6
  private const val MAC_BYTES = 6
  private const val REPETITIONS = 16

  /** 6 + 16 x 6. Asserted rather than derived at the call site, so a short packet cannot ship. */
  public const val PACKET_BYTES: Int = HEADER_BYTES + REPETITIONS * MAC_BYTES

  /**
   * Parses `a4:83:e7:1c:0b:2f`, `A4-83-E7-1C-0B-2F` or `a483e71c0b2f` into six bytes.
   *
   * Null rather than an exception for anything else: the address comes from the agent over the
   * network, so a malformed one is an ordinary condition the caller has to say something about, not
   * a programming error.
   */
  public fun parseMac(mac: String): ByteArray? {
    val hex = mac.filter { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }
    if (hex.length != MAC_BYTES * 2) return null
    return ByteArray(MAC_BYTES) { i -> hex.substring(i * 2, i * 2 + 2).toInt(HEX_RADIX).toByte() }
  }

  /** The packet for [mac], or null when the address is not one. */
  public fun packetFor(mac: String): ByteArray? = parseMac(mac)?.let(::packet)

  public fun packet(mac: ByteArray): ByteArray {
    require(mac.size == MAC_BYTES) { "a MAC address is $MAC_BYTES bytes, got ${mac.size}" }
    val bytes = ByteArray(PACKET_BYTES)
    for (i in 0 until HEADER_BYTES) bytes[i] = SYNC_BYTE
    for (repeat in 0 until REPETITIONS) {
      mac.copyInto(bytes, HEADER_BYTES + repeat * MAC_BYTES)
    }
    return bytes
  }

  private const val HEX_RADIX = 16
  private const val SYNC_BYTE: Byte = 0xFF.toByte()
}
