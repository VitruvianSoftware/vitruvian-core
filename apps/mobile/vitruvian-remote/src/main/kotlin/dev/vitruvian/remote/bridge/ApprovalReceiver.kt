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

/**
 * The Approve and Deny buttons on an approval notification.
 *
 * A receiver rather than an activity because answering must not open the app: the phone is in a
 * hand, the notification is on the lock screen, and the answer is one tap. `exported="false"` in
 * the manifest is load-bearing -- these two intents ARE the consent for sending a text, and any app
 * on the phone could otherwise broadcast them.
 */
public class ApprovalReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val id = intent.getStringExtra(EXTRA_ID) ?: return
    // attach() first: the receiver can be the FIRST thing in this process to
    // run after a low-memory kill, with the hub holding none of its state.
    BridgeHub.attach(context)
    when (intent.action) {
      ACTION_APPROVE -> BridgeHub.answer(id, true)
      ACTION_DENY -> BridgeHub.answer(id, false)
      else -> Unit
    }
  }

  public companion object {
    public const val ACTION_APPROVE: String = "dev.vitruvian.remote.bridge.APPROVE"
    public const val ACTION_DENY: String = "dev.vitruvian.remote.bridge.DENY"
    public const val EXTRA_ID: String = "call_id"
  }
}
