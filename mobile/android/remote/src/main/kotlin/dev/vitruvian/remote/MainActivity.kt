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
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import dev.vitruvian.remote.hid.BluetoothHidTransport
import dev.vitruvian.remote.hid.HidAction
import dev.vitruvian.remote.state.DeepLink
import dev.vitruvian.remote.state.Notifier
import dev.vitruvian.remote.state.Persistence
import dev.vitruvian.remote.state.PhoneClipboard
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.Screen

/**
 * The single activity.
 *
 * Edge-to-edge because the shell draws its own bars and applies the safe insets to them itself -
 * the language's 55 dp top bar is 55 dp *plus* the status inset, not 55 dp inclusive of it.
 */
public class MainActivity : ComponentActivity() {

  private lateinit var hid: BluetoothHidTransport
  private lateinit var state: RemoteState

  /** Ask once per launch, not on every focus change (returning from the dialog is one). */
  private var askedForBluetooth = false
  private var askedForNotifications = false

  private val requestNotifications =
      registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        // Nothing to do either way. Denied means NotificationManagerCompat
        // drops what we post, which is the user's decision; the app does not
        // change behaviour and does not ask again.
      }

  // Registered unconditionally: a launcher must exist before onCreate returns,
  // so it cannot be created lazily inside the version check below.
  private val requestBluetooth =
      registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        // start() is safe either way -- without the permission it stays
        // Unavailable rather than throwing. Calling it on denial keeps the one
        // code path instead of two.
        if (granted) hid.start()
        // One dialog at a time: the second is asked for only once the first is
        // out of the way, or Android drops it.
        askForNotifications()
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

    // The state holder is created first so the transport can report link
    // changes straight into it -- that is what drives the trackpad caption
    // between "drag to move" and "not connected".
    hid = BluetoothHidTransport(this) { link -> state.onHidLinkChanged(link) }
    state =
        RemoteState(
            persistence = Persistence(this),
            hid = hid,
            phoneClipboard = SystemClipboard(this),
            notifier = ShadeNotifier(this),
        )
    setContent { RemoteApp(state) }
    handleIntent(intent)
  }

  /** A deep link, or a tile, arriving at an activity that is already running. */
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleIntent(intent)
  }

  /**
   * Routes what launched us.
   *
   * Two things can: a `vitruvian-remote://<screen>` link (from a notification, this app's own or
   * the agent's ntfy `Click` header) and a Quick Settings tile, which carries an action extra
   * instead of a URL because it is asking for a key press rather than a screen.
   */
  private fun handleIntent(intent: Intent?) {
    if (intent == null) return
    DeepLink.screen(intent.data?.toString())?.let { key ->
      Screen.entries.firstOrNull { it.name.equals(key, ignoreCase = true) }?.let(state::go)
    }
    when (intent.getStringExtra(EXTRA_ACTION)) {
      ACTION_DISPLAY_SLEEP -> state.runTileAction(HidAction.DisplaySleepChord)
      ACTION_LOCK_MAC -> state.runTileAction(HidAction.LockScreen)
      else -> Unit
    }
    // Consumed: without this, every configuration change re-delivers the same
    // extra and the Mac's display sleeps again on each rotation.
    intent.removeExtra(EXTRA_ACTION)
  }

  override fun onResume() {
    super.onResume()
    state.onForeground(true)
  }

  override fun onPause() {
    // From here on a finished command is worth a notification: nobody is
    // looking at the output.
    state.onForeground(false)
    super.onPause()
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
      askForNotifications()
      return
    }
    requestBluetooth.launch(Manifest.permission.BLUETOOTH_CONNECT)
  }

  /**
   * Asks for the notification permission, after the first frame, exactly like Bluetooth above.
   *
   * Same first-run bug applies: a permission dialog in front of an app that has not painted yet can
   * leave the activity undrawn. Notifications became a runtime permission in API 33; below that the
   * channel alone is enough.
   */
  private fun askForNotifications() {
    if (askedForNotifications) return
    askedForNotifications = true
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    if (ContextCompat.checkSelfPermission(this, PERMISSION_POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED) {
      return
    }
    requestNotifications.launch(PERMISSION_POST_NOTIFICATIONS)
  }

  override fun onStop() {
    // Give the HID profile back when we are not on screen. Holding it would
    // keep the phone advertising as a keyboard indefinitely, which is both
    // rude to the Mac and a battery cost for a remote nobody is looking at.
    hid.stop()
    super.onStop()
  }

  public companion object {
    /** The extra a Quick Settings tile sets, and the two values it can carry. */
    public const val EXTRA_ACTION: String = "action"
    public const val ACTION_DISPLAY_SLEEP: String = "display_sleep"
    public const val ACTION_LOCK_MAC: String = "lock_mac"

    /**
     * `Manifest.permission.POST_NOTIFICATIONS` by name.
     *
     * Spelled out rather than referenced so this file compiles against an SDK older than 33, where
     * the constant does not exist -- the runtime check above already guards the use.
     */
    private const val PERMISSION_POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
  }
}

/**
 * The phone's notification shade, behind the model's port.
 *
 * One channel, at default importance: these are "your Mac stopped answering" and "the build you
 * started has finished", which are worth a glance and not worth a full-screen interruption.
 *
 * The channel is created on every construction because that call is idempotent -- creating a
 * channel that exists changes nothing, and there is no other moment in this app's lifecycle that is
 * guaranteed to run before the first notification.
 */
private class ShadeNotifier(private val context: Context) : Notifier {
  init {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel =
          NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT)
      channel.description = "Your Mac going quiet, and commands that finish in the background."
      context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
  }

  override fun notify(id: String, title: String, body: String, deepLink: String) {
    val intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(deepLink), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
    val pending =
        PendingIntent.getActivity(
            context,
            id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    val notification =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tile_display_sleep)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
    // Wrapped: posting without POST_NOTIFICATIONS throws nothing on most
    // builds but has thrown SecurityException on some, and a notification is
    // never important enough to take the app down with it.
    runCatching { NotificationManagerCompat.from(context).notify(id, id.hashCode(), notification) }
  }

  private companion object {
    const val CHANNEL_ID = "vitruvian-remote"
    const val CHANNEL_NAME = "Vitruvian Remote"
  }
}

/**
 * The phone's clipboard, behind the model's port.
 *
 * `coerceToText` rather than `text`: a copied URL or styled span arrives as an Intent or a Spanned
 * and `item.text` is null for both, which would have made "push" silently do nothing for exactly
 * the content most worth pushing to a Mac.
 *
 * From Android 12 a read raises the system's "pasted from" toast. That is correct and stays: this
 * app reads the clipboard only when the user presses Push, and the notification is the user's
 * confirmation that it happened.
 */
private class SystemClipboard(private val context: Context) : PhoneClipboard {
  private val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

  override fun read(): String =
      manager.primaryClip
          ?.takeIf { it.itemCount > 0 }
          ?.getItemAt(0)
          ?.coerceToText(context)
          ?.toString()
          .orEmpty()

  override fun write(text: String) {
    manager.setPrimaryClip(ClipData.newPlainText("Vitruvian Remote", text))
  }
}
