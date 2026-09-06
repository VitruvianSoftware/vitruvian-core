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

package dev.vitruvian.remote

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import dev.vitruvian.remote.hid.BluetoothHidTransport
import dev.vitruvian.remote.state.Persistence
import dev.vitruvian.remote.state.RemoteState

/**
 * The single activity.
 *
 * Edge-to-edge because the shell draws its own bars and applies the safe insets to them itself -
 * the language's 55 dp top bar is 55 dp *plus* the status inset, not 55 dp inclusive of it.
 */
public class MainActivity : ComponentActivity() {

  private lateinit var hid: BluetoothHidTransport

  /** Ask once per launch, not on every focus change (returning from the dialog is one). */
  private var askedForBluetooth = false

  // Registered unconditionally: a launcher must exist before onCreate returns,
  // so it cannot be created lazily inside the version check below.
  private val requestBluetooth =
      registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        // start() is safe either way -- without the permission it stays
        // Unavailable rather than throwing. Calling it on denial keeps the one
        // code path instead of two.
        if (granted) hid.start()
      }

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)

    // A remote that blanks itself mid-use is not a remote. The phone is being
    // held and looked at for the whole time it is in the foreground, and the
    // system idle timeout has no way to know that -- it sees no touches while
    // you watch the Mac react. Released automatically when the activity leaves
    // the foreground, so it costs nothing when the app is not on screen.
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

    hid = BluetoothHidTransport(this)
    val state = RemoteState(persistence = Persistence(this), hid = hid)
    setContent { RemoteApp(state) }
  }

  override fun onStart() {
    super.onStart()
    // Unconditional: start() no-ops without the permission rather than
    // throwing, so there is one path here instead of two, and a user who
    // already granted the permission is connected before the window is even up.
    hid.start()
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
    if (!hasFocus || askedForBluetooth) return
    askedForBluetooth = true

    // Ask only once the window is actually up, NOT in onStart.
    //
    // Requesting during startup puts the system permission dialog in front of
    // an app that has not painted yet, and on a fresh install the activity then
    // never draws at all -- GrantPermissionsActivity is simply left on top.
    // Verified on an emulator: with the permission ungranted the app logs no
    // first frame whatsoever; granted, it draws in ~900 ms. That is a first-run
    // bug in its own right, and it is what //mobile/android/remote:boot_smoke
    // caught.
    //
    // onWindowFocusChanged(true) is the first callback that is guaranteed to
    // follow the first frame, which is exactly the ordering needed.
    //
    // BLUETOOTH_CONNECT became a runtime permission in API 31; below that the
    // install-time permissions in the manifest cover it and asking would fail
    // on a permission the platform does not know.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
        PackageManager.PERMISSION_GRANTED) {
      return
    }
    requestBluetooth.launch(Manifest.permission.BLUETOOTH_CONNECT)
  }

  override fun onStop() {
    // Give the HID profile back when we are not on screen. Holding it would
    // keep the phone advertising as a keyboard indefinitely, which is both
    // rude to the Mac and a battery cost for a remote nobody is looking at.
    hid.stop()
    super.onStop()
  }
}
