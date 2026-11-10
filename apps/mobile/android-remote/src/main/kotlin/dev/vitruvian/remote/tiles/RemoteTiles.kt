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
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import dev.vitruvian.remote.MainActivity
import dev.vitruvian.remote.state.AgentClient
import dev.vitruvian.remote.state.AgentHostEntry
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.Persistence
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * The Quick Settings tiles.
 *
 * Sleep display and Lock Mac are HID key presses, so they work with no agent and no pairing -- the
 * phone IS the keyboard. SpeakerMuteTile talks directly to the Mac agent's `/v1/homespeaker/volume`
 * endpoint without launching the activity.
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

/**
 * Quick Settings tile that mutes or unmutes HomeSpeaker on the selected Mac without launching the
 * app or unlocking the phone.
 */
public class SpeakerMuteTile : TileService() {
  private var listenScope: CoroutineScope? = null
  private val clickScope: CoroutineScope =
      CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private var currentMuted: Boolean? = null

  override fun onStartListening() {
    super.onStartListening()
    listenScope?.cancel()
    val tileScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    listenScope = tileScope
    val host = selectedPairedHost()
    if (host == null) {
      currentMuted = null
      applySpec(Derive.speakerTileState(paired = false, reachable = false))
      return
    }
    tileScope.launch {
      val volume =
          runCatching {
                withTimeout(TILE_TIMEOUT_MS) {
                  AgentClient(host.url, host.token)
                      .homeSpeakerVolume(readTimeoutMs = TILE_READ_TIMEOUT_MS)
                }
              }
              .getOrNull()
      if (volume == null) {
        currentMuted = null
        applySpec(Derive.speakerTileState(paired = true, reachable = false))
      } else {
        currentMuted = if (volume.available && volume.online) volume.muted else null
        applySpec(
            Derive.speakerTileState(
                paired = true,
                reachable = true,
                available = volume.available,
                online = volume.online,
                muted = volume.muted,
                percent = volume.percent,
            ))
      }
    }
  }

  override fun onStopListening() {
    listenScope?.cancel()
    listenScope = null
    super.onStopListening()
  }

  override fun onDestroy() {
    listenScope?.cancel()
    listenScope = null
    clickScope.cancel()
    super.onDestroy()
  }

  override fun onClick() {
    super.onClick()
    val host = selectedPairedHost()
    if (host == null) {
      currentMuted = null
      applySpec(Derive.speakerTileState(paired = false, reachable = false))
      return
    }
    listenScope?.cancel()
    val currentlyMuted = currentMuted ?: (qsTile?.state == Tile.STATE_INACTIVE)
    val nextMuted = !currentlyMuted
    clickScope.launch {
      val updated =
          runCatching {
                withTimeout(TILE_TIMEOUT_MS) {
                  AgentClient(host.url, host.token)
                      .setHomeSpeakerVolume(muted = nextMuted, readTimeoutMs = TILE_READ_TIMEOUT_MS)
                }
              }
              .getOrNull()
      if (updated == null) {
        applySpec(Derive.speakerTileState(paired = true, reachable = false, clickFailed = true))
      } else {
        currentMuted = if (updated.available && updated.online) updated.muted else null
        applySpec(
            Derive.speakerTileState(
                paired = true,
                reachable = true,
                available = updated.available,
                online = updated.online,
                muted = updated.muted,
                percent = updated.percent,
            ))
      }
    }
  }

  private fun selectedPairedHost(): AgentHostEntry? {
    val store = Persistence(applicationContext)
    val selectedId = store.selectedHostId
    val host = store.hosts.firstOrNull { it.id == selectedId } ?: store.hosts.firstOrNull()
    if (host == null || host.url.isBlank() || host.token.isBlank()) return null
    return host
  }

  private fun applySpec(spec: Derive.SpeakerTileSpec) {
    val tile = qsTile ?: return
    tile.state =
        when (spec.look) {
          Derive.SpeakerTileLook.Unavailable -> Tile.STATE_UNAVAILABLE
          Derive.SpeakerTileLook.Inactive -> Tile.STATE_INACTIVE
          Derive.SpeakerTileLook.Active -> Tile.STATE_ACTIVE
        }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      tile.subtitle = spec.subtitle
    }
    tile.contentDescription = "Speaker, ${spec.subtitle}"
    tile.updateTile()
  }

  private companion object {
    const val TILE_TIMEOUT_MS = 3_000L
    const val TILE_READ_TIMEOUT_MS = 3_000
  }
}
