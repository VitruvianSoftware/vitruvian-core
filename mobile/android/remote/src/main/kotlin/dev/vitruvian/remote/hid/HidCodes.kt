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
   * The mouse, which the ESP32 does not have.
   *
   * The board is keyboard + consumer only, so unlike everything else in this file there is no
   * firmware to copy: the trackpad, both click buttons and scrolling all hang off this collection
   * and it is written from the HID spec rather than ported.
   *
   * Adding it changes the report descriptor, and macOS CACHES the descriptor per paired device --
   * so a Mac paired before this shipped must forget the phone and pair again before the pointer
   * works. That is the reason to add the whole mouse at once rather than a piece at a time.
   */
  public const val MOUSE_REPORT_ID: Int = 3

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

  // Mouse button bits, byte 0 of a mouse report.
  public const val MOUSE_BUTTON_NONE: Int = 0x00
  public const val MOUSE_BUTTON_LEFT: Int = 0x01
  public const val MOUSE_BUTTON_RIGHT: Int = 0x02
  public const val MOUSE_BUTTON_MIDDLE: Int = 0x04

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
   * macOS's "Put Display to Sleep" is Ctrl+Shift+Power. The ESP32 sends consumer usage 0x30 for
   * this and it does nothing from the phone.
   *
   * I first blamed the transport -- the board is BLE, this is Bluetooth Classic. James's read is
   * simpler and fits better: that button probably never worked on the board either, and 0x30 is
   * just the wrong code. Either way, this chord is the one verified against a real Mac, and
   * iot/esp32-s3 likely wants the same correction.
   *
   * Note 0x66 is 102, one past the 0..101 key array this descriptor declares. macOS accepts it
   * regardless; verified on hardware. Do not "fix" the range to make it legal -- that is an
   * untested change to a working descriptor, and macOS caches the descriptor per paired device so a
   * mistake only surfaces after a re-pair.
   */
  public const val KEY_POWER: Int = 0x66

  // The rest of the keyboard page, as raw HID usages. Named rather than
  // inlined so a chord below reads as the shortcut a Mac user already knows.
  public const val KEY_A: Int = 0x04
  public const val KEY_C: Int = 0x06
  public const val KEY_D: Int = 0x07
  public const val KEY_F: Int = 0x09
  public const val KEY_H: Int = 0x0B
  public const val KEY_M: Int = 0x10
  public const val KEY_N: Int = 0x11
  public const val KEY_T: Int = 0x17
  public const val KEY_V: Int = 0x19
  public const val KEY_W: Int = 0x1A
  public const val KEY_X: Int = 0x1B
  public const val KEY_Z: Int = 0x1D
  public const val KEY_3: Int = 0x20
  public const val KEY_4: Int = 0x21
  public const val KEY_5: Int = 0x22
  public const val KEY_RETURN: Int = 0x28
  public const val KEY_ESCAPE: Int = 0x29
  public const val KEY_BACKSPACE: Int = 0x2A
  public const val KEY_TAB: Int = 0x2B
  public const val KEY_SPACE: Int = 0x2C
  public const val KEY_GRAVE: Int = 0x35
  public const val KEY_F3: Int = 0x3C
  public const val KEY_F4: Int = 0x3D
  public const val KEY_DOWN_ARROW: Int = 0x51

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
          // --- Mouse ---
          // Relative pointer, three buttons and a wheel. Written from the HID
          // spec: the ESP32 has no mouse to copy.
          0x05,
          0x01, // Usage Page (Generic Desktop)
          0x09,
          0x02, // Usage (Mouse)
          0xA1.toByte(),
          0x01, // Collection (Application)
          0x85.toByte(),
          MOUSE_REPORT_ID.toByte(),
          0x09,
          0x01, //   Usage (Pointer)
          0xA1.toByte(),
          0x00, //   Collection (Physical)
          // Buttons 1..3 as single bits, then 5 bits of padding to byte-align.
          0x05,
          0x09, //     Usage Page (Button)
          0x19,
          0x01, //     Usage Min (Button 1)
          0x29,
          0x03, //     Usage Max (Button 3)
          0x15,
          0x00, //     Logical Min (0)
          0x25,
          0x01, //     Logical Max (1)
          0x75,
          0x01, //     Report Size (1)
          0x95.toByte(),
          0x03, //     Report Count (3)
          0x81.toByte(),
          0x02, //     Input (Data, Var, Abs)
          0x75,
          0x05, //     Report Size (5)
          0x95.toByte(),
          0x01, //     Report Count (1)
          0x81.toByte(),
          0x03, //     Input (Const) -- padding
          // X, Y and wheel as signed 8-bit RELATIVE deltas. Relative, not
          // absolute: a trackpad reports movement, and the host owns where the
          // cursor actually is. -127..127 per report; larger gestures are split
          // across reports by the caller.
          0x05,
          0x01, //     Usage Page (Generic Desktop)
          0x09,
          0x30, //     Usage (X)
          0x09,
          0x31, //     Usage (Y)
          0x09,
          0x38, //     Usage (Wheel)
          0x15,
          0x81.toByte(), //     Logical Min (-127)
          0x25,
          0x7F, //     Logical Max (127)
          0x75,
          0x08, //     Report Size (8)
          0x95.toByte(),
          0x03, //     Report Count (3)
          0x81.toByte(),
          0x06, //     Input (Data, Var, Rel)
          0xC0.toByte(), //   End Collection (Physical)
          0xC0.toByte(), // End Collection
      )

  /**
   * Marks an entry in [ASCII_TO_USAGE] as needing Shift.
   *
   * The table packs "which key" and "with shift?" into one byte, exactly as the firmware does: low
   * 7 bits are the usage, the high bit is the shift flag.
   */
  private const val SHIFT_FLAG = 0x80

  /**
   * ASCII to HID keyboard usage, ported byte-for-byte from `ble_hid.cpp`.
   *
   * This is a US layout. A Mac set to a different keyboard layout will produce different characters
   * for the punctuation entries -- HID carries key POSITIONS, not letters, and the host decides
   * what each position means. Nothing here can fix that; it would need the layout the Mac is using.
   *
   * Index is the ASCII code. 0 means "no key for this character".
   */
  @JvmField
  @Suppress("MagicNumber")
  public val ASCII_TO_USAGE: IntArray =
      intArrayOf(
          // NUL..BEL
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          // BS TAB LF, then unmapped control codes
          0x2A,
          0x2B,
          0x28,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          // ' ' ! " #
          0x2C,
          0x1E or SHIFT_FLAG,
          0x34 or SHIFT_FLAG,
          0x20 or SHIFT_FLAG,
          // $ % & '
          0x21 or SHIFT_FLAG,
          0x22 or SHIFT_FLAG,
          0x24 or SHIFT_FLAG,
          0x34,
          // ( ) * +
          0x26 or SHIFT_FLAG,
          0x27 or SHIFT_FLAG,
          0x25 or SHIFT_FLAG,
          0x2E or SHIFT_FLAG,
          // , - . /
          0x36,
          0x2D,
          0x37,
          0x38,
          // 0..7
          0x27,
          0x1E,
          0x1F,
          0x20,
          0x21,
          0x22,
          0x23,
          0x24,
          // 8 9 : ;
          0x25,
          0x26,
          0x33 or SHIFT_FLAG,
          0x33,
          // < = > ?
          0x36 or SHIFT_FLAG,
          0x2E,
          0x37 or SHIFT_FLAG,
          0x38 or SHIFT_FLAG,
          // @ A B C
          0x1F or SHIFT_FLAG,
          0x04 or SHIFT_FLAG,
          0x05 or SHIFT_FLAG,
          0x06 or SHIFT_FLAG,
          // D E F G
          0x07 or SHIFT_FLAG,
          0x08 or SHIFT_FLAG,
          0x09 or SHIFT_FLAG,
          0x0A or SHIFT_FLAG,
          // H I J K
          0x0B or SHIFT_FLAG,
          0x0C or SHIFT_FLAG,
          0x0D or SHIFT_FLAG,
          0x0E or SHIFT_FLAG,
          // L M N O
          0x0F or SHIFT_FLAG,
          0x10 or SHIFT_FLAG,
          0x11 or SHIFT_FLAG,
          0x12 or SHIFT_FLAG,
          // P Q R S
          0x13 or SHIFT_FLAG,
          0x14 or SHIFT_FLAG,
          0x15 or SHIFT_FLAG,
          0x16 or SHIFT_FLAG,
          // T U V W
          0x17 or SHIFT_FLAG,
          0x18 or SHIFT_FLAG,
          0x19 or SHIFT_FLAG,
          0x1A or SHIFT_FLAG,
          // X Y Z [
          0x1B or SHIFT_FLAG,
          0x1C or SHIFT_FLAG,
          0x1D or SHIFT_FLAG,
          0x2F,
          // \ ] ^ _
          0x31,
          0x30,
          0x23 or SHIFT_FLAG,
          0x2D or SHIFT_FLAG,
          // ` a b c
          0x35,
          0x04,
          0x05,
          0x06,
          // d e f g
          0x07,
          0x08,
          0x09,
          0x0A,
          // h i j k
          0x0B,
          0x0C,
          0x0D,
          0x0E,
          // l m n o
          0x0F,
          0x10,
          0x11,
          0x12,
          // p q r s
          0x13,
          0x14,
          0x15,
          0x16,
          // t u v w
          0x17,
          0x18,
          0x19,
          0x1A,
          // x y z {
          0x1B,
          0x1C,
          0x1D,
          0x2F or SHIFT_FLAG,
          // | } ~ DEL
          0x31 or SHIFT_FLAG,
          0x30 or SHIFT_FLAG,
          0x35 or SHIFT_FLAG,
          0,
      )

  /**
   * The keystroke for one character, or null if this layout cannot type it.
   *
   * Null rather than a silent no-op so the caller can say which characters were dropped instead of
   * the Mac quietly receiving a shorter string than the user typed.
   */
  public fun keyFor(char: Char): HidAction.Key? {
    val code = char.code
    if (code !in ASCII_TO_USAGE.indices) return null
    val entry = ASCII_TO_USAGE[code]
    if (entry == 0) return null
    val modifiers = if (entry and SHIFT_FLAG != 0) MOD_SHIFT else MOD_NONE
    return HidAction.Key(modifiers, entry and 0x7F)
  }

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

  /**
   * A mouse report: `[buttons, dx, dy, wheel]`.
   *
   * Deltas are clamped to the signed 8-bit range the descriptor declares. Clamping rather than
   * wrapping matters: a delta of 200 wrapped into a byte becomes -56, and the pointer jumps
   * backwards instead of far forwards. Callers split large movements across several reports.
   */
  public fun mouseReport(buttons: Int, dx: Int, dy: Int, wheel: Int = 0): ByteArray =
      byteArrayOf(
          (buttons and 0x07).toByte(),
          dx.coerceIn(-127, 127).toByte(),
          dy.coerceIn(-127, 127).toByte(),
          wheel.coerceIn(-127, 127).toByte(),
      )

  /** Buttons up, no movement. */
  public fun mouseRelease(): ByteArray = byteArrayOf(0, 0, 0, 0)
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

    // --- Desktop and Spaces -------------------------------------------
    // The four the ESP32 ships, plus the rest of what macOS exposes to a
    // keyboard. Every one of these is a documented system shortcut, not a
    // guess: if one does not fire, the shortcut is disabled or remapped in
    // System Settings > Keyboard rather than the code being wrong.

    /** Ctrl+Down: all windows of the FRONT app, unlike Mission Control's everything. */
    public val AppExpose: HidAction = Key(HidCodes.MOD_CTRL, HidCodes.KEY_DOWN_ARROW)

    /** F4 opens Launchpad on a standard Apple keyboard layout. */
    public val Launchpad: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_F4)

    /** Cmd+Space. The single most-used shortcut on the machine. */
    public val Spotlight: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_SPACE)

    // --- Screenshots ---------------------------------------------------
    public val ScreenshotFull: HidAction =
        Key(HidCodes.MOD_CMD or HidCodes.MOD_SHIFT, HidCodes.KEY_3)
    public val ScreenshotRegion: HidAction =
        Key(HidCodes.MOD_CMD or HidCodes.MOD_SHIFT, HidCodes.KEY_4)

    /** Cmd+Shift+5 opens the capture UI rather than taking a shot immediately. */
    public val ScreenshotUi: HidAction = Key(HidCodes.MOD_CMD or HidCodes.MOD_SHIFT, HidCodes.KEY_5)

    // --- Windows and apps ----------------------------------------------
    //
    // CmdTab is a single press: it switches to the previous app and releases.
    // Holding Cmd to walk a longer list needs the modifier held ACROSS reports,
    // which this fire-and-forget action cannot express -- see HidSender.
    public val CmdTab: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_TAB)
    public val CycleWindows: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_GRAVE)
    public val CloseWindow: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_W)
    public val MinimiseWindow: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_M)
    public val HideApp: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_H)
    public val QuitApp: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_Q)
    public val Fullscreen: HidAction = Key(HidCodes.MOD_CTRL or HidCodes.MOD_CMD, HidCodes.KEY_F)

    /** Cmd+Opt+Esc. Destructive enough that the UI should confirm before sending it. */
    public val ForceQuit: HidAction = Key(HidCodes.MOD_CMD or HidCodes.MOD_ALT, HidCodes.KEY_ESCAPE)

    // --- Editing --------------------------------------------------------
    public val Copy: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_C)
    public val Paste: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_V)
    public val Cut: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_X)
    public val Undo: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_Z)
    public val SelectAll: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_A)
    public val NewTab: HidAction = Key(HidCodes.MOD_CMD, HidCodes.KEY_T)

    // --- Bare keys, for the on-screen palette ---------------------------
    public val Escape: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_ESCAPE)
    public val Tab: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_TAB)
    public val Return: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_RETURN)
    public val Backspace: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_BACKSPACE)
    public val ArrowUp: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_UP_ARROW)
    public val ArrowDown: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_DOWN_ARROW)
    public val ArrowLeft: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_LEFT_ARROW)
    public val ArrowRight: HidAction = Key(HidCodes.MOD_NONE, HidCodes.KEY_RIGHT_ARROW)

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
public interface HidSender {
  /** Returns false when there is no connected host, so callers can say so rather than pretend. */
  public fun send(action: HidAction): Boolean

  /**
   * Relative pointer movement, button state and scroll, as one mouse report.
   *
   * Deliberately NOT modelled as a [HidAction]. An action is a press followed by an automatic
   * release, which is right for a key and wrong for a pointer: movement is a stream, and a drag
   * needs the button held across many reports. The caller owns press and release here.
   *
   * Deltas beyond the signed-byte range are clamped, so a caller moving a long way must split it
   * across calls rather than expect one report to carry it.
   */
  public fun sendPointer(
      dx: Int,
      dy: Int,
      buttons: Int = HidCodes.MOUSE_BUTTON_NONE,
      wheel: Int = 0
  ): Boolean

  /**
   * Types a sequence of keystrokes IN ORDER, each fully pressed and released before the next.
   *
   * [send] cannot simply be looped to type a word. It releases asynchronously after a dwell, so a
   * loop fires every press before any release lands: two identical characters in a row collapse
   * into one, because the host never sees a key-up between them, and the stray releases interleave
   * with later presses. Typing has to be serialised, so it gets its own entry point.
   *
   * Returns false immediately when there is no host. The sending itself happens off the caller's
   * thread: a hundred characters at a 20 ms dwell is several seconds and must not block the UI.
   */
  public fun sendSequence(keys: List<HidAction.Key>): Boolean
}
