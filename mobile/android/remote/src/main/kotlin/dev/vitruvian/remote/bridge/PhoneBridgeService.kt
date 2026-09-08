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

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import dev.vitruvian.remote.MainActivity
import dev.vitruvian.remote.R
import dev.vitruvian.remote.state.AgentClient
import dev.vitruvian.remote.state.AgentHostEntry
import dev.vitruvian.remote.state.BridgeDecision
import dev.vitruvian.remote.state.BridgePolicy
import dev.vitruvian.remote.state.DeepLink
import dev.vitruvian.remote.state.ExecStreamHandle
import dev.vitruvian.remote.state.Persistence
import dev.vitruvian.remote.state.SseEvent
import dev.vitruvian.remote.state.ToolTier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * The phone's half of the bridge: one outbound link to the Mac agent, held open.
 *
 * A foreground service because that is the only way Android keeps a socket alive while the phone is
 * in a pocket. `dataSync` is the type: this is a long-lived transfer with the user's own machine,
 * and the notification it obliges us to show is the feature -- it says whether the link is up and
 * how long agents stay trusted, and it carries the Stop button.
 *
 * The phone never listens. It dials out, reads `call` events, runs the tool, and posts the answer
 * back. That is what makes this work over cellular, behind NAT, with no second pairing and no wifi
 * debugging -- see `docs/phone-bridge.md`.
 */
public class PhoneBridgeService : Service() {

  private val registry = ToolRegistry()
  private var scope: CoroutineScope? = null
  private var link: Job? = null
  private val handle = ExecStreamHandle()

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    BridgeHub.attach(this)
    // Extension point for Part 2: register the notification-listener and
    // accessibility tools here, beside these. Nothing downstream needs to
    // know they exist -- the descriptor list, the tier gate, the approval
    // prompt and the audit trail all read from the registry.
    registry.registerAll(PhoneTools.standard(applicationContext))
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_STOP) {
      // A user-pressed Stop must also mean "stay stopped": without this the
      // next app launch would start the bridge again and look like a bug.
      BridgeHub.setEnabled(false)
      stop()
      return START_NOT_STICKY
    }
    startForegroundNotification()
    if (link == null) {
      val created = CoroutineScope(SupervisorJob() + Dispatchers.IO)
      scope = created
      link = created.launch { linkLoop() }
      created.launch { notificationTicker() }
    }
    // STICKY: the system killing this for memory is exactly the case where the
    // bridge should come back on its own -- the phone is in a pocket and
    // nobody is going to notice it went quiet.
    return START_STICKY
  }

  override fun onDestroy() {
    stop()
    super.onDestroy()
  }

  private fun stop() {
    handle.cancel()
    link = null
    scope?.cancel()
    scope = null
    BridgeHub.setLink(false, "off")
    ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  // --- the link ---------------------------------------------------------

  /**
   * Dials the Mac, reads until the stream ends, waits, dials again.
   *
   * Backoff doubles from two seconds to a minute because the two reasons a link ends are opposite:
   * the agent restarting (back in seconds) and the phone being somewhere with no signal (back in
   * however long the train takes). A fixed two-second retry would be a battery drain in the second
   * case; a fixed minute would make the first case feel broken.
   */
  private suspend fun linkLoop() {
    var backoffMs = MIN_BACKOFF_MS
    val store = Persistence(applicationContext)
    while (scope?.isActive == true) {
      val host = selectedHost(store)
      when {
        host == null || host.url.isBlank() ->
            BridgeHub.setLink(false, "no Mac selected — add one on the Hosts screen")
        host.token.isBlank() ->
            BridgeHub.setLink(
                false,
                "not paired with ${host.alias.ifBlank { "the Mac" }} — pair on the Hosts screen")
        else -> connect(host)
      }
      if (handle.cancelled) return
      delay(backoffMs)
      backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
      // A link that came up and stayed up resets the wait: an agent restarting
      // twice in a morning should not leave the phone waiting a minute.
      if (BridgeHub.linked) backoffMs = MIN_BACKOFF_MS
    }
  }

  private suspend fun connect(host: AgentHostEntry) {
    val client = AgentClient(host.url, host.token)
    val body =
        BridgePolicy.encodeLinkBody(
            model = Build.MODEL.orEmpty(),
            android = Build.VERSION.RELEASE.orEmpty(),
            tools = registry.descriptors(),
        )
    BridgeHub.setLink(false, "connecting to ${host.alias.ifBlank { "the Mac" }}…")
    updateNotification()
    runCatching { client.phoneLink(body, handle) { event -> onEvent(client, event) } }
        .onFailure { failure ->
          BridgeHub.setLink(false, failure.message?.lineSequence()?.first() ?: "no answer")
        }
    if (!handle.cancelled && BridgeHub.linked) {
      BridgeHub.setLink(false, "the Mac closed the link")
    }
    updateNotification()
  }

  /**
   * One event off the link.
   *
   * A `call` is dispatched to its own coroutine on purpose: a tool that waits sixty seconds for
   * someone to tap Approve must not stop the reader, or the `ping` that proves the link is alive
   * would be sixty seconds late and a second call could not arrive at all.
   */
  private fun onEvent(client: AgentClient, event: SseEvent) {
    when (event.name) {
      "hello" -> {
        BridgeHub.setLink(true, "linked")
        updateNotification()
      }
      "ping" -> Unit
      "call" -> {
        val o = runCatching { JSONObject(event.data) }.getOrNull() ?: return
        val id = o.optString("id")
        val name = o.optString("tool")
        val arguments = o.optJSONObject("arguments") ?: JSONObject()
        if (id.isBlank() || name.isBlank()) return
        scope?.launch { handleCall(client, id, name, arguments) }
      }
      else -> Unit
    }
  }

  /** The approval rule, the tool, the audit line and the answer, in that order. */
  private suspend fun handleCall(
      client: AgentClient,
      id: String,
      name: String,
      arguments: JSONObject,
  ) {
    val summary = BridgePolicy.summarize(flatten(arguments))
    val tool = registry.get(name)
    if (tool == null) {
      BridgeHub.record(name, summary, "no such tool", "—")
      client.phoneResult(id, "this phone has no tool called $name", true)
      return
    }
    val decision = BridgePolicy.decide(tool.tier, BridgeHub.trustUntil, System.currentTimeMillis())
    val approver: String
    when (decision) {
      is BridgeDecision.Deny -> {
        BridgeHub.record(name, summary, "denied", "trust window closed")
        client.phoneResult(id, decision.reason, true)
        return
      }
      BridgeDecision.Allow ->
          // Read tools are never gated; act and outbound got here because the
          // window is open, and the audit line must say which of the two it was.
          approver = if (tool.tier == ToolTier.Read) "read tier" else "trust window"
      BridgeDecision.Prompt -> {
        val answer = BridgeHub.awaitApproval(id, name, question(name, arguments))
        when (answer) {
          null -> {
            BridgeHub.record(name, summary, "no answer", "nobody")
            client.phoneResult(id, BridgePolicy.NO_ANSWER, true)
            return
          }
          false -> {
            BridgeHub.record(name, summary, "denied", "person")
            client.phoneResult(id, BridgePolicy.REFUSED, true)
            return
          }
          true -> approver = "approved"
        }
      }
    }
    val result =
        runCatching { withContext(Dispatchers.IO) { tool.call(arguments) } }
            .getOrElse { ToolResult("the tool failed: ${it.message}", true) }
    BridgeHub.record(name, summary, if (result.isError) "error" else "ok", approver)
    client.phoneResult(id, result.text, result.isError)
  }

  /**
   * The sentence on the approval notification.
   *
   * Names the recipient and quotes the start of the message, because "an agent wants to send an
   * SMS" is not something anyone can answer: what makes the difference between yes and no is who it
   * is going to and what it says.
   */
  private fun question(name: String, arguments: JSONObject): String =
      when (name) {
        "sms.send" ->
            "send SMS to ${arguments.optString("to")} : " +
                "\"${arguments.optString("body").take(BridgePolicy.TEXT_VALUE_MAX)}…\""
        "calls.dial" -> "call ${arguments.optString("number")}"
        else -> "run $name ${BridgePolicy.summarize(flatten(arguments))}"
      }

  private fun flatten(arguments: JSONObject): List<Pair<String, String>> =
      arguments
          .keys()
          .asSequence()
          .map { key -> key to arguments.opt(key)?.toString().orEmpty() }
          .toList()

  private fun selectedHost(store: Persistence): AgentHostEntry? {
    val hosts = store.hosts
    val id = store.selectedHostId
    return hosts.firstOrNull { it.id == id } ?: hosts.firstOrNull()
  }

  // --- the notification -------------------------------------------------

  private fun startForegroundNotification() {
    val type =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
          0
        }
    ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), type)
  }

  /**
   * Redraws the notification while nothing else is happening.
   *
   * The trust window is a countdown, and a countdown that only updates when a tool runs is a
   * countdown that says "58 min left" an hour after it closed.
   */
  private suspend fun notificationTicker() {
    while (scope?.isActive == true) {
      updateNotification()
      delay(TICK_MS)
    }
  }

  private fun updateNotification() {
    runCatching {
      getSystemService(android.app.NotificationManager::class.java)
          ?.notify(NOTIFICATION_ID, buildNotification())
    }
  }

  private fun buildNotification(): Notification {
    val open = BridgeHub.trustOpen()
    val trust = if (open) "agents trusted · ${BridgeHub.trustRemaining()}" else "agents not trusted"
    val stop =
        PendingIntent.getService(
            this,
            0,
            Intent(this, PhoneBridgeService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    val openApp =
        PendingIntent.getActivity(
            this,
            1,
            Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse(DeepLink.uriFor("hosts")),
                    this,
                    MainActivity::class.java,
                )
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    return NotificationCompat.Builder(this, BridgeHub.CHANNEL_LINK)
        .setSmallIcon(R.drawable.ic_tile_display_sleep)
        .setContentTitle(
            if (BridgeHub.linked) "Phone bridge · linked"
            else "Phone bridge · ${BridgeHub.linkStatus}")
        .setContentText(trust)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setContentIntent(openApp)
        .addAction(0, "Stop bridge", stop)
        .build()
  }

  public companion object {
    /** The notification action, and what the Stop button sends. */
    public const val ACTION_STOP: String = "dev.vitruvian.remote.bridge.STOP"

    private const val NOTIFICATION_ID = 0x8101
    private const val MIN_BACKOFF_MS = 2_000L
    private const val MAX_BACKOFF_MS = 60_000L
    private const val TICK_MS = 30_000L

    /** Starts the bridge. Safe to call when it is already running. */
    public fun start(context: Context) {
      ContextCompat.startForegroundService(context, Intent(context, PhoneBridgeService::class.java))
    }

    /** Stops it, through the same path the notification's button uses. */
    public fun stop(context: Context) {
      runCatching {
        context.startService(Intent(context, PhoneBridgeService::class.java).setAction(ACTION_STOP))
      }
    }
  }
}
