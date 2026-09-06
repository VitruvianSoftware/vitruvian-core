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

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "VitruvianHid"

/**
 * What the app can tell the user about the Bluetooth link, without leaking Android types upward.
 */
public enum class HidLinkState {
  /** No permission, no Bluetooth, or the platform is too old. Nothing will work. */
  Unavailable,

  /** Registered as a HID device, waiting for a Mac to connect to us. */
  WaitingForHost,

  /** A host is connected; [BluetoothHidTransport.send] will actually do something. */
  Connected,
}

/**
 * Presents the phone to macOS as a Bluetooth keyboard, so the remote can drive a Mac with **no
 * software installed on the Mac at all**.
 *
 * This is the ESP32's trick ported to Android: `iot/esp32-s3` already pairs to a Mac as an ordinary
 * BLE keyboard and sends the same reports. [HidCodes] is that firmware's report map and key codes;
 * this class is only the platform glue around them.
 *
 * ## What it does and does not replace
 *
 * It covers the CONTROL half of the app -- media, volume, spaces, mission control. It does nothing
 * for the dashboards: CPU, memory, thermals, Lima, Docker and K3s all still need the Mac agent,
 * because a keyboard can press keys and cannot report numbers. Treating this as "the app is
 * finished" would be wrong.
 *
 * ## Pairing
 *
 * The Mac pairs with the phone through the SYSTEM Bluetooth settings, as it would with any
 * keyboard. That is not the six-digit code the Hosts screen currently draws -- that flow belongs to
 * the agent, and the two need reconciling before this is user-facing.
 */
public class BluetoothHidTransport(private val context: Context) : HidSender {

  private val scope = CoroutineScope(Dispatchers.Default)
  private val executor = Executors.newSingleThreadExecutor()

  private var proxy: BluetoothHidDevice? = null
  private var host: BluetoothDevice? = null
  private var adapter: BluetoothAdapter? = null

  /**
   * Guards against registering twice.
   *
   * start() is called from onStart AND from the permission callback, and each call asks for a fresh
   * profile proxy. The second registerApp then fails with "another app is registered" and takes the
   * FIRST registration down with it, leaving the remote connected to nothing. Cheap to prevent,
   * confusing to debug: the log shows registered=true immediately followed by registered=false.
   */
  private var starting = false

  /** Observable enough for the UI without exposing Bluetooth types to it. */
  public var state: HidLinkState = HidLinkState.Unavailable
    private set

  private val sdp =
      BluetoothHidDeviceAppSdpSettings(
          "Vitruvian Remote",
          "Foldable-first Mac remote",
          "VitruvianSoftware",
          // Matches the ESP32's advertised appearance: macOS decides how to
          // treat the device from this, and COMBO/other gets handled less
          // predictably than a plain keyboard.
          BluetoothHidDevice.SUBCLASS1_KEYBOARD,
          HidCodes.REPORT_MAP,
      )

  private val callback =
      object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
          Log.i(TAG, "app status: registered=$registered")
          state = if (registered) HidLinkState.WaitingForHost else HidLinkState.Unavailable
          // Registering only makes us CONNECTABLE. macOS will not open a
          // keyboard link on its own just because a bond exists -- a Mac can
          // sit paired-but-not-connected indefinitely -- so we make the first
          // move.
          if (registered) connectToPairedComputer()
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, connectionState: Int) {
          Log.i(TAG, "connection state: $connectionState")
          when (connectionState) {
            BluetoothProfile.STATE_CONNECTED -> {
              host = device
              state = HidLinkState.Connected
            }
            BluetoothProfile.STATE_DISCONNECTED -> {
              host = null
              state = HidLinkState.WaitingForHost
            }
          }
        }
      }

  private val serviceListener =
      object : BluetoothProfile.ServiceListener {
        @SuppressLint("MissingPermission")
        override fun onServiceConnected(profile: Int, service: BluetoothProfile?) {
          if (profile != BluetoothProfile.HID_DEVICE) return
          starting = false
          val hid = service as? BluetoothHidDevice ?: return
          proxy = hid
          if (!hasConnectPermission()) {
            Log.w(TAG, "BLUETOOTH_CONNECT not granted; not registering")
            return
          }
          hid.registerApp(sdp, null, null, executor, callback)
        }

        override fun onServiceDisconnected(profile: Int) {
          if (profile != BluetoothProfile.HID_DEVICE) return
          starting = false
          proxy = null
          host = null
          state = HidLinkState.Unavailable
        }
      }

  /**
   * Starts advertising as a keyboard. Safe to call when Bluetooth is off or the permission is
   * missing -- it simply stays [HidLinkState.Unavailable].
   */
  public fun start() {
    if (starting || proxy != null) return
    // BluetoothHidDevice is API 28+. The app's minSdk is 26, so this is a real
    // check rather than a formality: on 26/27 the whole class is absent.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
      Log.i(TAG, "HID device profile needs API 28; this device is ${Build.VERSION.SDK_INT}")
      return
    }
    val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
    val adapter: BluetoothAdapter = manager.adapter ?: return
    if (!adapter.isEnabled) {
      Log.i(TAG, "Bluetooth is off")
      return
    }
    this.adapter = adapter
    starting = true
    adapter.getProfileProxy(context, serviceListener, BluetoothProfile.HID_DEVICE)
  }

  /**
   * Asks every paired COMPUTER to accept us as a keyboard.
   *
   * Pairing and connecting are different things: the Mac can be bonded to the phone for years and
   * still have no HID link open. Waiting for the host is therefore a dead end in practice, and this
   * is the call that actually gets a keyboard talking.
   *
   * Filtered to [BluetoothClass.Device.Major.COMPUTER] rather than trying every bond, because
   * offering a keyboard connection to a pair of earbuds is noise. Returns true if at least one
   * request was accepted for delivery -- not that a host answered, which arrives later on
   * [BluetoothHidDevice.Callback.onConnectionStateChanged].
   */
  @SuppressLint("MissingPermission")
  public fun connectToPairedComputer(): Boolean {
    val hid = proxy ?: return false
    val adapter = this.adapter ?: return false
    if (!hasConnectPermission()) return false

    val computers =
        adapter.bondedDevices.orEmpty().filter {
          it.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.COMPUTER
        }
    if (computers.isEmpty()) {
      Log.i(TAG, "no paired computer to connect to; pair the Mac first")
      return false
    }
    var requested = false
    for (device in computers) {
      val ok = runCatching { hid.connect(device) }.getOrDefault(false)
      Log.i(TAG, "connect request -> accepted=$ok")
      requested = requested || ok
    }
    return requested
  }

  /** Stops advertising and releases the proxy. */
  @SuppressLint("MissingPermission")
  public fun stop() {
    val hid = proxy ?: return
    if (hasConnectPermission()) {
      runCatching { hid.unregisterApp() }
    }
    proxy = null
    host = null
    state = HidLinkState.Unavailable
  }

  /**
   * Sends one action, press then release.
   *
   * The release is not optional and not merely tidy: without it a modifier stays latched on the Mac
   * and every subsequent keystroke the USER types is modified. The dwell between them is
   * [HidCodes.KEY_DWELL_MS] because macOS drops a press/release pair delivered in the same
   * event-loop turn -- with no dwell the button appears to do nothing.
   *
   * Returns false when there is no connected host, so callers can fall back rather than pretend the
   * Mac received something.
   */
  @SuppressLint("MissingPermission")
  override fun send(action: HidAction): Boolean {
    val hid = proxy ?: return false
    val target = host ?: return false
    if (!hasConnectPermission()) return false

    val (id, press, release) =
        when (action) {
          is HidAction.Key ->
              Triple(
                  HidCodes.KEYBOARD_REPORT_ID,
                  HidCodes.keyboardReport(action.modifiers, action.usage),
                  HidCodes.keyboardRelease(),
              )
          is HidAction.Consumer ->
              Triple(
                  HidCodes.CONSUMER_REPORT_ID,
                  HidCodes.consumerReport(action.usage),
                  HidCodes.consumerRelease(),
              )
        }

    if (!hid.sendReport(target, id, press)) {
      Log.w(TAG, "sendReport(press) refused for $action")
      return false
    }
    // Released off the caller's thread so a tap never blocks the UI for the
    // dwell. Failure to release is logged rather than swallowed: a stuck
    // modifier is the worst outcome this class can produce.
    scope.launch {
      delay(HidCodes.KEY_DWELL_MS)
      if (!hid.sendReport(target, id, release)) {
        Log.e(TAG, "sendReport(release) refused for $action -- a key may be stuck on the host")
      }
    }
    return true
  }

  /**
   * Sends one mouse report. No auto-release: the caller decides when a button comes up, because a
   * drag holds it down across many reports.
   */
  @SuppressLint("MissingPermission")
  override fun sendPointer(dx: Int, dy: Int, buttons: Int, wheel: Int): Boolean {
    val hid = proxy ?: return false
    val target = host ?: return false
    if (!hasConnectPermission()) return false
    return hid.sendReport(
        target, HidCodes.MOUSE_REPORT_ID, HidCodes.mouseReport(buttons, dx, dy, wheel))
  }

  private fun hasConnectPermission(): Boolean =
      // BLUETOOTH_CONNECT only exists from API 31; below that the legacy
      // install-time BLUETOOTH permission covers it.
      Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
          ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
              PackageManager.PERMISSION_GRANTED
}
