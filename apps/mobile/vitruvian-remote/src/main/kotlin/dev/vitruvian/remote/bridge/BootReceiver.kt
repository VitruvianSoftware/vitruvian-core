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

package dev.vitruvian.remote.bridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.vitruvian.remote.state.BridgeRestartPolicy

/**
 * Restarts Phone Bridge after a reboot (`BOOT_COMPLETED`) or an app update (`MY_PACKAGE_REPLACED`)
 * when the user left it switched on.
 *
 * Uses `BOOT_COMPLETED` rather than `LOCKED_BOOT_COMPLETED` because `bridgeEnabled` and the paired
 * host token live in credential-encrypted `SharedPreferences`, which Android unlocks only after the
 * user's first unlock. `exported="false"` in the manifest blocks other apps from sending explicit
 * intents here while still allowing `system_server` to deliver both protected broadcasts.
 */
public class BootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    BridgeHub.attach(context)
    if (!BridgeRestartPolicy.shouldRestartOnBroadcast(intent.action, BridgeHub.enabled())) return
    if (!BridgeHub.linked) BridgeHub.setLink(false, "starting…")
    // Keep the caller-side catch in case startForegroundService itself throws; on
    // Android 15+ a type-specific refusal surfaces inside PhoneBridgeService.onStartCommand,
    // where startForegroundNotification catches it and stops with START_NOT_STICKY.
    runCatching { PhoneBridgeService.start(context) }
        .onFailure {
          val outcome = BridgeRestartPolicy.onStartRefused(BridgeHub.enabled())
          BridgeHub.setLink(false, outcome.linkStatus)
        }
  }
}
