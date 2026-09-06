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

package dev.vitruvian.remote.hid

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the HID wire format to what `iot/esp32-s3/src/ble_hid.cpp` actually sends.
 *
 * Why this test is worth more than it looks: a wrong byte here produces a device that pairs,
 * connects, reports no error and does nothing. There is no crash and no log line -- the Mac simply
 * ignores a report it cannot parse. Nothing downstream can catch that, so the bytes are asserted
 * literally rather than by re-deriving them from the same constants that would be wrong.
 */
class HidCodesTest {

  @Test
  fun `keyboard report matches the firmware layout`() {
    // Firmware: uint8_t report[8] = {0}; report[0] = modifiers; report[2] = usage;
    val report = HidCodes.keyboardReport(HidCodes.MOD_CTRL, HidCodes.KEY_UP_ARROW)

    assertEquals("report is 8 bytes: modifiers, reserved, then 6 key slots", 8, report.size)
    assertEquals("byte 0 carries the modifier bits", 0x01.toByte(), report[0])
    assertEquals("byte 1 is reserved and MUST stay zero", 0x00.toByte(), report[1])
    assertEquals("byte 2 is the first key slot", 0x52.toByte(), report[2])
    for (i in 3 until 8) {
      assertEquals("unused key slot $i must be zero", 0x00.toByte(), report[i])
    }
  }

  @Test
  fun `release clears every key`() {
    assertArrayEquals(ByteArray(8), HidCodes.keyboardRelease())
    assertArrayEquals(byteArrayOf(0, 0), HidCodes.consumerRelease())
  }

  @Test
  fun `consumer report is little-endian`() {
    // Firmware: {(uint8_t)(cons & 0xFF), (uint8_t)(cons >> 8)}
    // Volume up is 0x00E9, so low byte first: E9 00. Big-endian would send
    // 00 E9, which the host reads as usage 0 -- silently nothing.
    assertArrayEquals(
        byteArrayOf(0xE9.toByte(), 0x00),
        HidCodes.consumerReport(HidCodes.CONSUMER_VOLUME_UP),
    )
    // A usage that spans both bytes, so the ordering cannot pass by accident
    // the way an 8-bit value would.
    assertArrayEquals(byteArrayOf(0x34, 0x02), HidCodes.consumerReport(0x0234))
  }

  @Test
  fun `key usages are the firmware's Arduino constants minus 136`() {
    // ble_hid.cpp: `if (key >= 136) report[2] = key - 136;`
    // These are the four the board actually sends, resolved.
    assertEquals("KEY_UP_ARROW 0xDA", 218 - 136, HidCodes.KEY_UP_ARROW)
    assertEquals("KEY_LEFT_ARROW 0xD8", 216 - 136, HidCodes.KEY_LEFT_ARROW)
    assertEquals("KEY_RIGHT_ARROW 0xD7", 215 - 136, HidCodes.KEY_RIGHT_ARROW)
    assertEquals("KEY_F11 0xCC", 204 - 136, HidCodes.KEY_F11)
  }

  @Test
  fun `the four Mac chords match mac_hid cpp`() {
    assertEquals(
        "mission control is Ctrl+Up",
        HidAction.Key(HidCodes.MOD_CTRL, 0x52),
        HidAction.MissionControl,
    )
    assertEquals("show desktop is bare F11", HidAction.Key(0x00, 0x44), HidAction.ShowDesktop)
    assertEquals("space left is Ctrl+Left", HidAction.Key(0x01, 0x50), HidAction.SpaceLeft)
    assertEquals("space right is Ctrl+Right", HidAction.Key(0x01, 0x4F), HidAction.SpaceRight)
  }

  @Test
  fun `display sleep keeps the firmware's power usage`() {
    // 0x30 is Power, not a literal "display sleep" usage. macOS treats it as
    // display sleep and the board relies on that; "correcting" it to something
    // more literal would be an untested change dressed up as a fix.
    assertEquals(0x0030, HidCodes.CONSUMER_DISPLAY_SLEEP)
  }

  @Test
  fun `report map is byte-for-byte the firmware descriptor`() {
    val map = HidCodes.REPORT_MAP

    // Structure the host parses: two application collections, one per report.
    assertEquals("starts with Usage Page (Generic Desktop)", 0x05.toByte(), map[0])
    assertEquals(0x01.toByte(), map[1])
    assertEquals("Usage (Keyboard)", 0x09.toByte(), map[2])
    assertEquals(0x06.toByte(), map[3])
    assertEquals("ends with End Collection", 0xC0.toByte(), map[map.size - 1])

    // Report IDs appear behind 0x85 tags, and must match the IDs used when
    // sending -- a mismatch is the classic "connects but does nothing".
    val keyboardIdAt = map.indexOfFirst { it == 0x85.toByte() }
    assertEquals(
        "keyboard collection declares report id 1",
        HidCodes.KEYBOARD_REPORT_ID.toByte(),
        map[keyboardIdAt + 1],
    )
    val consumerIdAt =
        map.toList().subList(keyboardIdAt + 1, map.size).indexOfFirst { it == 0x85.toByte() } +
            keyboardIdAt +
            1
    assertEquals(
        "consumer collection declares report id 2",
        HidCodes.CONSUMER_REPORT_ID.toByte(),
        map[consumerIdAt + 1],
    )

    // The consumer collection must be on the Consumer page, or media keys land
    // on the wrong usage page and are ignored.
    assertTrue(
        "descriptor contains Usage Page (Consumer) 0x05 0x0C",
        map.toList().windowed(2).any { it[0] == 0x05.toByte() && it[1] == 0x0C.toByte() },
    )
  }

  @Test
  fun `Keyboard Power is usable even though the array declares a max of 101`() {
    // Keyboard Power is usage 0x66 = 102, and this descriptor -- copied from
    // the firmware -- declares the key array as 0..101. By the letter of the
    // HID spec that puts Power out of range.
    //
    // macOS accepts it anyway. That is not a guess: Ctrl+Shift+Power sleeps the
    // display on a real Mac with this exact descriptor cached, verified on
    // hardware. Hosts commonly treat the array's Logical/Usage Max as advisory.
    //
    // Recorded because the obvious "fix" -- widening the range to 0..255 -- is
    // an UNTESTED change to a descriptor that currently works, and macOS caches
    // the descriptor per paired device, so getting it wrong is only discovered
    // after a re-pair. Leave the descriptor matching the firmware.
    assertEquals("Keyboard Power", 0x66, HidCodes.KEY_POWER)

    val map = HidCodes.REPORT_MAP.toList()
    assertTrue(
        "descriptor still declares the firmware's 0..101 key array",
        map.windowed(2).any { it[0] == 0x29.toByte() && it[1] == 0x65.toByte() },
    )
  }

  @Test
  fun `display sleep is a keyboard chord, not a consumer usage`() {
    // Verified against a real Mac: Ctrl+Shift+Power sleeps the display and
    // leaves the machine running. Consumer 0x30 -- what the board sends -- is
    // enumerated by macOS and then ignored over Bluetooth Classic.
    assertEquals(
        HidAction.Key(HidCodes.MOD_CTRL or HidCodes.MOD_SHIFT, 0x66),
        HidAction.DisplaySleepChord,
    )
    // Lock is a DIFFERENT thing and must not quietly become the sleep action:
    // it demands a password on return, which display sleep does not.
    assertEquals(
        HidAction.Key(HidCodes.MOD_CTRL or HidCodes.MOD_CMD, 0x14),
        HidAction.LockScreen,
    )
  }

  @Test
  fun `dwell is long enough for macOS to register the press`() {
    // Firmware HID_KEY_DWELL_MS. A zero dwell sends press and release in the
    // same event-loop turn and WindowServer drops the pair -- the button
    // appears to do nothing at all.
    assertEquals(20L, HidCodes.KEY_DWELL_MS)
  }

  @Test
  fun `mouse report is buttons then signed dx dy wheel`() {
    val r = HidCodes.mouseReport(HidCodes.MOUSE_BUTTON_LEFT, dx = 5, dy = -3, wheel = 1)
    assertEquals("4 bytes: buttons, dx, dy, wheel", 4, r.size)
    assertEquals("left button is bit 0", 0x01.toByte(), r[0])
    assertEquals(5.toByte(), r[1])
    assertEquals("negative dy must stay negative", (-3).toByte(), r[2])
    assertEquals(1.toByte(), r[3])
  }

  @Test
  fun `oversized deltas clamp rather than wrap`() {
    // The descriptor declares -127..127. A raw byte cast of 200 is -56, so a
    // fast swipe right would send the pointer LEFT. Clamping keeps the
    // direction and the caller splits the remainder across reports.
    val r = HidCodes.mouseReport(HidCodes.MOUSE_BUTTON_NONE, dx = 200, dy = -200, wheel = 0)
    assertEquals("dx clamps to +127, never wraps negative", 127.toByte(), r[1])
    assertEquals("dy clamps to -127", (-127).toByte(), r[2])
  }

  @Test
  fun `only the three button bits are used`() {
    // Byte 0 has 3 button bits and 5 bits of declared padding. Letting a stray
    // high bit through sets a button the host does not know about.
    val r = HidCodes.mouseReport(0xFF, dx = 0, dy = 0)
    assertEquals(0x07.toByte(), r[0])
  }

  @Test
  fun `mouse release clears buttons and movement`() {
    assertArrayEquals(byteArrayOf(0, 0, 0, 0), HidCodes.mouseRelease())
  }

  @Test
  fun `descriptor declares a mouse with relative axes`() {
    val map = HidCodes.REPORT_MAP.toList()

    // Usage (Mouse) = 0x09 0x02 on the Generic Desktop page.
    assertTrue(
        "descriptor must declare Usage (Mouse)",
        map.windowed(2).any { it[0] == 0x09.toByte() && it[1] == 0x02.toByte() },
    )
    // Input (Data, Var, Rel) = 0x81 0x06. RELATIVE is the whole point: 0x02
    // (absolute) would make the pointer treat deltas as screen coordinates and
    // pin it to the top-left corner.
    assertTrue(
        "axes must be relative (0x81 0x06), not absolute",
        map.windowed(2).any { it[0] == 0x81.toByte() && it[1] == 0x06.toByte() },
    )
    // Three report IDs now: keyboard, consumer, mouse.
    assertEquals(
        "three report-ID declarations",
        3,
        map.windowed(2).count { it[0] == 0x85.toByte() },
    )
    assertTrue(
        "mouse collection declares report id 3",
        map.windowed(2).any {
          it[0] == 0x85.toByte() && it[1] == HidCodes.MOUSE_REPORT_ID.toByte()
        },
    )
  }

  @Test
  fun `letters map to their usage, uppercase adds shift`() {
    // 'a' is usage 0x04 and the alphabet runs contiguously from there.
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, 0x04), HidCodes.keyFor('a'))
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, 0x1D), HidCodes.keyFor('z'))
    // Same KEY, plus shift. HID has no notion of a capital letter -- it sends
    // the position and the modifier, and the host produces the character.
    assertEquals(HidAction.Key(HidCodes.MOD_SHIFT, 0x04), HidCodes.keyFor('A'))
    assertEquals(HidAction.Key(HidCodes.MOD_SHIFT, 0x1D), HidCodes.keyFor('Z'))
  }

  @Test
  fun `digits are not in numeric order on the keyboard page`() {
    // The trap: '1'..'9' are 0x1E..0x26, and '0' is 0x27 -- AFTER the nine,
    // not before the one. Deriving these arithmetically gets every digit wrong.
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, 0x1E), HidCodes.keyFor('1'))
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, 0x26), HidCodes.keyFor('9'))
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, 0x27), HidCodes.keyFor('0'))
  }

  @Test
  fun `shifted punctuation shares the unshifted key`() {
    // Every one of these is the same physical key with and without shift.
    // Getting the pairing wrong types a plausible but different character,
    // which is far worse than typing nothing.
    val pairs = listOf('1' to '!', '2' to '@', '3' to '#', '9' to '(', ';' to ':', '/' to '?')
    for ((plain, shifted) in pairs) {
      val a = HidCodes.keyFor(plain)!!
      val b = HidCodes.keyFor(shifted)!!
      assertEquals("$plain and $shifted are the same key", a.usage, b.usage)
      assertEquals("$plain is unshifted", HidCodes.MOD_NONE, a.modifiers)
      assertEquals("$shifted is shifted", HidCodes.MOD_SHIFT, b.modifiers)
    }
  }

  @Test
  fun `space newline and tab are typeable`() {
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, 0x2C), HidCodes.keyFor(' '))
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, HidCodes.KEY_RETURN), HidCodes.keyFor('\n'))
    assertEquals(HidAction.Key(HidCodes.MOD_NONE, HidCodes.KEY_TAB), HidCodes.keyFor('\t'))
  }

  @Test
  fun `untypeable characters return null rather than a silent no-op`() {
    // Non-ASCII has no place on a US layout. Returning null lets the caller
    // report what it dropped; returning a zero usage would send an empty
    // keystroke and the Mac would just receive a shorter string.
    assertEquals(null, HidCodes.keyFor('é'))
    assertEquals(null, HidCodes.keyFor('→'))
    assertEquals(null, HidCodes.keyFor('\u0000'))
  }

  @Test
  fun `every printable ASCII character is typeable`() {
    // 0x20..0x7E is the printable range. A gap here is a character the user
    // can enter on the phone and silently never arrives on the Mac.
    val missing = (0x20..0x7E).map { it.toChar() }.filter { HidCodes.keyFor(it) == null }
    assertTrue("no printable character may be unmapped, missing: $missing", missing.isEmpty())
  }
}
