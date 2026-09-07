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

package dev.vitruvian.remote.tiles

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService
import dev.vitruvian.remote.MainActivity

/**
 * The two Quick Settings tiles.
 *
 * The point is the two actions worth reaching from a locked phone without opening anything: put the
 * Mac's display to sleep, and lock it. Both are HID key presses, so they work with no agent and no
 * pairing -- the phone IS the keyboard.
 *
 * A tile cannot send the key press itself: the Bluetooth HID profile is held by the activity, and a
 * `TileService` is a different process lifecycle with nothing connected. So the tile launches the
 * app with an extra, and [MainActivity] waits for the link before sending -- or says why it could
 * not. That wait is the whole reason this is not fire-and-forget: a tile tapped from the lock
 * screen runs seconds before Bluetooth has finished connecting.
 */
public abstract class RemoteActionTile : TileService() {
  /** One of [MainActivity.ACTION_DISPLAY_SLEEP] or [MainActivity.ACTION_LOCK_MAC]. */
  protected abstract val action: String

  override fun onClick() {
    super.onClick()
    val intent =
        Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_ACTION, action)
    // From API 34 the Intent overload throws; before it, the PendingIntent
    // overload does not exist. Both collapse the shade and unlock first if the
    // device is locked, which is what a tile that drives a Mac needs.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      startActivityAndCollapse(
          PendingIntent.getActivity(
              this,
              action.hashCode(),
              intent,
              PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
          ))
    } else {
      @Suppress("DEPRECATION") startActivityAndCollapse(intent)
    }
  }
}

/** Ctrl+Shift+Power: displays off, session untouched. */
public class SleepDisplayTile : RemoteActionTile() {
  override val action: String = MainActivity.ACTION_DISPLAY_SLEEP
}

/** Ctrl+Cmd+Q: locked, and a password needed to get back in. */
public class LockMacTile : RemoteActionTile() {
  override val action: String = MainActivity.ACTION_LOCK_MAC
}
