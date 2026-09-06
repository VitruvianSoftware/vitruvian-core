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

/**
 * The HID wire format, ported from `iot/esp32-s3/src/ble_hid.cpp`.
 *
 * The ESP32 board already drives a Mac as a Bluetooth keyboard, with no software installed on the
 * Mac at all. This file is that same report map and the same key codes, so the phone presents
 * itself to macOS as the identical class of device. Nothing here is invented: where a value looks
 * arbitrary it is because the firmware proved that exact value works, and matching it is the point.
 *
 * Deliberately free of Android imports. The encoding is the part worth testing and the part most
 * likely to break silently -- a wrong byte produces a device that pairs, connects, reports no error
 * and does nothing -- so it lives here where a plain JVM test can pin it, and
 * [BluetoothHidTransport] holds the platform glue.
 */
public object HidCodes {

  /** Report IDs, matching `KEYBOARD_REPORT_ID` / `CONSUMER_REPORT_ID` in the firmware. */
  public const val KEYBOARD_REPORT_ID: Int = 1
  public const val CONSUMER_REPORT_ID: Int = 2

  /**
   * How long a key is held before release.
   *
   * The firmware's `HID_KEY_DWELL_MS`. It is not politeness: macOS's WindowServer drops a
   * press/release pair that arrives in the same event-loop turn, so a zero-dwell tap silently does
   * nothing. 20 ms is the value the board ships.
   */
  public const val KEY_DWELL_MS: Long = 20

  // Modifier bits in byte 0 of a keyboard report. Left-hand modifiers only,
  // which is all the firmware uses and all macOS needs.
  public const val MOD_NONE: Int = 0x00
  public const val MOD_CTRL: Int = 0x01
  public const val MOD_SHIFT: Int = 0x02
  public const val MOD_ALT: Int = 0x04
  public const val MOD_CMD: Int = 0x08

  // Raw HID keyboard usages (page 0x07).
  //
  // The firmware stores Arduino key constants and converts with `key - 136` at
  // send time; these are the post-conversion values, so KEY_UP_ARROW (0xDA =
  // 218) is 218 - 136 = 82 = 0x52 here. Storing the resolved usage removes a
  // translation step that exists on the board only for USB compatibility.
  public const val KEY_F11: Int = 0x44
  public const val KEY_RIGHT_ARROW: Int = 0x4F
  public const val KEY_LEFT_ARROW: Int = 0x50
  public const val KEY_UP_ARROW: Int = 0x52
  public const val KEY_Q: Int = 0x14

  /**
   * Keyboard Power (page 0x07, usage 0x66) -- NOT consumer Power (0x30).
   *
   * macOS's "Put Display to Sleep" is Ctrl+Shift+Power. The consumer route the ESP32 uses (0x30)
   * works over BLE and is silently ignored over Bluetooth Classic, which is the transport Android's
   * HID profile gives us -- macOS enumerates the consumer collection and then does nothing with it.
   *
   * Note 0x66 is 102, one past the 0..101 key array this descriptor declares. macOS accepts it
   * regardless; verified on hardware. Do not "fix" the range to make it legal -- that is an
   * untested change to a working descriptor, and macOS caches the descriptor per paired device so a
   * mistake only surfaces after a re-pair.
   */
  public const val KEY_POWER: Int = 0x66

  // Consumer page (0x0C) usages.
  public const val CONSUMER_PLAY_PAUSE: Int = 0x00CD
  public const val CONSUMER_SCAN_NEXT: Int = 0x00B5
  public const val CONSUMER_SCAN_PREVIOUS: Int = 0x00B6
  public const val CONSUMER_MUTE: Int = 0x00E2
  public const val CONSUMER_VOLUME_UP: Int = 0x00E9
  public const val CONSUMER_VOLUME_DOWN: Int = 0x00EA

  /**
   * What the firmware calls display sleep.
   *
   * 0x30 is `Power` in the consumer page, not a dedicated sleep usage. macOS treats it as "sleep
   * the display", which is why the board uses it. Kept identical rather than "corrected" to a more
   * literal usage that has not been tried against a real Mac.
   */
  public const val CONSUMER_DISPLAY_SLEEP: Int = 0x0030

  // Brightness. NOT on the ESP32 -- it has no brightness buttons -- so unlike
  // everything else here these two are standard-by-the-book rather than
  // proven-on-hardware. Flagged because that is a real difference in confidence.
  public const val CONSUMER_BRIGHTNESS_UP: Int = 0x006F
  public const val CONSUMER_BRIGHTNESS_DOWN: Int = 0x0070

  /**
   * The report map: keyboard (report 1) then consumer control (report 2).
   *
   * Byte-for-byte the firmware's `HID_REPORT_MAP`. A descriptor the host cannot parse produces a
   * device that connects and is simply ignored, so this is copied rather than re-derived.
   */
  @JvmField
  public val REPORT_MAP: ByteArray =
      byteArrayOf(
          // --- Keyboard ---
          0x05,
          0x01, // Usage Page (Generic Desktop)
          0x09,
          0x06, // Usage (Keyboard)
          0xA1.toByte(),
          0x01, // Collection (Application)
          0x85.toByte(),
          KEYBOARD_REPORT_ID.toByte(),
          0x05,
          0x07, //   Usage Page (Key Codes)
          0x19,
          0xE0.toByte(), //   Usage Min (224: Left Ctrl)
          0x29,
          0xE7.toByte(), //   Usage Max (231: Right GUI)
          0x15,
          0x00, //   Logical Min (0)
          0x25,
          0x01, //   Logical Max (1)
          0x75,
          0x01, //   Report Size (1)
          0x95.toByte(),
          0x08, //   Report Count (8)
          0x81.toByte(),
          0x02, //   Input (Data, Var, Abs) -- modifier byte
          0x95.toByte(),
          0x01, //   Report Count (1)
          0x75,
          0x08, //   Report Size (8)
          0x81.toByte(),
          0x01, //   Input (Const) -- reserved byte
          0x95.toByte(),
          0x06, //   Report Count (6)
          0x75,
          0x08, //   Report Size (8)
          0x15,
          0x00, //   Logical Min (0)
          0x25,
          0x65, //   Logical Max (101)
          0x05,
          0x07, //   Usage Page (Key Codes)
          0x19,
          0x00, //   Usage Min (0)
          0x29,
          0x65, //   Usage Max (101)
          0x81.toByte(),
          0x00, //   Input (Data, Array) -- 6-key rollover
          0xC0.toByte(), // End Collection
          // --- Consumer Control ---
          0x05,
          0x0C, // Usage Page (Consumer)
          0x09,
          0x01, // Usage (Consumer Control)
          0xA1.toByte(),
          0x01, // Collection (Application)
          0x85.toByte(),
          CONSUMER_REPORT_ID.toByte(),
          0x15,
          0x00, //   Logical Min (0)
          0x26,
          0xFF.toByte(),
          0x03, //   Logical Max (0x3FF)
          0x19,
          0x00, //   Usage Min (0)
          0x2A,
          0xFF.toByte(),
          0x03, //   Usage Max (0x3FF)
          0x75,
          0x10, //   Report Size (16)
          0x95.toByte(),
          0x01, //   Report Count (1)
          0x81.toByte(),
          0x00, //   Input (Data, Array)
          0xC0.toByte(), // End Collection
      )

  /**
   * A keyboard report: `[modifiers, reserved, key1..key6]`.
   *
   * Only one key is ever set; the app sends chords like Ctrl+Up, never true multi-key rollover.
   */
  public fun keyboardReport(modifiers: Int, usage: Int): ByteArray {
    val report = ByteArray(8)
    report[0] = modifiers.toByte()
    report[2] = usage.toByte()
    return report
  }

  /** All keys up. Sent after [KEY_DWELL_MS] so a press cannot stick if the app dies mid-action. */
  public fun keyboardRelease(): ByteArray = ByteArray(8)

  /** A consumer report: one 16-bit usage, little-endian, exactly as the firmware packs it. */
  public fun consumerReport(usage: Int): ByteArray =
      byteArrayOf((usage and 0xFF).toByte(), ((usage shr 8) and 0xFF).toByte())

  /** Nothing pressed. */
  public fun consumerRelease(): ByteArray = byteArrayOf(0, 0)
}

/**
 * One thing the remote can do to the Mac.
 *
 * Modelled as data rather than as calls so the mapping is inspectable and testable on its own: the
 * whole surface is a table, and [HidAction.entries] is the complete list of what this transport
 * supports.
 */
public sealed interface HidAction {
  /** A key chord, e.g. Ctrl+Up for Mission Control. */
  public data class Key(val modifiers: Int, val usage: Int) : HidAction

  /** A media / system key from the consumer page. */
  public data class Consumer(val usage: Int) : HidAction

  public companion object {
    // The four Mac-specific chords the ESP32 ships, with its exact codes.
    public val MissionControl: HidAction = Key(HidCodes.MOD_CTRL, HidCodes.KEY_UP_ARROW)
    public val ShowDesktop: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_F11)
    public val SpaceLeft: HidAction = Key(HidCodes.MOD_CTRL, HidCodes.KEY_LEFT_ARROW)
    public val SpaceRight: HidAction = Key(HidCodes.MOD_CTRL, HidCodes.KEY_RIGHT_ARROW)

    /**
     * Lock the screen -- Ctrl+Cmd+Q on macOS, which blanks the display.
     *
     * Deliberately a KEYBOARD chord. macOS enumerates both our collections but does not act on
     * consumer 0x30 (Power) over Bluetooth Classic, where the ESP32's BLE link does -- so the
     * consumer route to a dark screen is not available to us and this is. Verified on a real Mac
     * rather than assumed.
     */
    public val LockScreen: HidAction = Key(HidCodes.MOD_CTRL or HidCodes.MOD_CMD, HidCodes.KEY_Q)

    /**
     * Put the display to sleep, leaving the machine awake: Ctrl+Shift+Power.
     *
     * The same thing Control Center's "Put Display to Sleep" does. Distinct from [LockScreen],
     * which blanks the screen but also demands a password on return.
     */
    public val DisplaySleepChord: HidAction =
        Key(HidCodes.MOD_CTRL or HidCodes.MOD_SHIFT, HidCodes.KEY_POWER)

    public val PlayPause: HidAction = Consumer(HidCodes.CONSUMER_PLAY_PAUSE)
    public val NextTrack: HidAction = Consumer(HidCodes.CONSUMER_SCAN_NEXT)
    public val PreviousTrack: HidAction = Consumer(HidCodes.CONSUMER_SCAN_PREVIOUS)
    public val Mute: HidAction = Consumer(HidCodes.CONSUMER_MUTE)
    public val VolumeUp: HidAction = Consumer(HidCodes.CONSUMER_VOLUME_UP)
    public val VolumeDown: HidAction = Consumer(HidCodes.CONSUMER_VOLUME_DOWN)
    public val DisplaySleep: HidAction = Consumer(HidCodes.CONSUMER_DISPLAY_SLEEP)
    public val BrightnessUp: HidAction = Consumer(HidCodes.CONSUMER_BRIGHTNESS_UP)
    public val BrightnessDown: HidAction = Consumer(HidCodes.CONSUMER_BRIGHTNESS_DOWN)
  }
}

/**
 * Somewhere to send an action.
 *
 * Exists so `RemoteState` depends on this one method rather than on Android's Bluetooth stack: the
 * state holder stays a plain object that a JVM test can drive with a fake, and
 * [BluetoothHidTransport] is the only thing that needs a device.
 */
public fun interface HidSender {
  /** Returns false when there is no connected host, so callers can say so rather than pretend. */
  public fun send(action: HidAction): Boolean
}
