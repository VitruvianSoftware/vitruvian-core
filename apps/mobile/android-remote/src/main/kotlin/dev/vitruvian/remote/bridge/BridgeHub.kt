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

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import dev.vitruvian.remote.R
import dev.vitruvian.remote.state.BridgeAuditEntry
import dev.vitruvian.remote.state.BridgePolicy
import dev.vitruvian.remote.state.Persistence
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * One phone permission the bridge needs, and the exact sentence to say when it is missing.
 *
 * [howTo] is not a description of the problem, it is the next step: it names the plate, the row and
 * the button, because this text is what the agent on the Mac reads back to a person who is holding
 * the phone and cannot see why the tool refused.
 */
public data class BridgePermission(
    /** Stable key: what the UI row and the audit entry hang off. */
    val id: String,
    val label: String,
    /**
     * The Android runtime permission, or null for one that is granted somewhere in Settings rather
     * than by a dialog -- notification access and the accessibility service.
     */
    val permission: String?,
    /** Which tools stop working without it. */
    val tools: String,
    val howTo: String,
    /**
     * The Settings screen that grants it, for a row that has no runtime permission.
     *
     * Notification access and the accessibility service cannot be asked for with a dialog: Android
     * only grants them from their own Settings pages. So the Grant button on those rows opens the
     * page instead of raising a prompt -- which is the difference between one tap and reading a
     * path out of an error message and going hunting for it.
     */
    val settingsAction: String? = null,
) {
  /** Whether the plate can offer a button at all -- a dialog, or the Settings page. */
  val grantable: Boolean
    get() = permission != null || settingsAction != null
}

/**
 * The permissions this slice's tools need.
 *
 * Six runtime permissions and two Settings switches. The order is the order of the plate, and the
 * two switches come last because they are the two that cost a trip out of the app.
 */
public object BridgePermissions {
  public val ROWS: List<BridgePermission> =
      listOf(
          BridgePermission(
              id = "read_sms",
              label = "Read SMS",
              permission = Manifest.permission.READ_SMS,
              tools = "sms.list",
              howTo = "Grant SMS: Hosts → Phone bridge → Read SMS → Grant.",
          ),
          BridgePermission(
              id = "send_sms",
              label = "Send SMS",
              permission = Manifest.permission.SEND_SMS,
              tools = "sms.send",
              howTo = "Grant SMS: Hosts → Phone bridge → Send SMS → Grant.",
          ),
          BridgePermission(
              id = "read_contacts",
              label = "Contacts",
              permission = Manifest.permission.READ_CONTACTS,
              tools = "contacts.search",
              howTo = "Grant Contacts: Hosts → Phone bridge → Contacts → Grant.",
          ),
          BridgePermission(
              id = "read_call_log",
              label = "Call log",
              permission = Manifest.permission.READ_CALL_LOG,
              tools = "calls.log",
              howTo = "Grant Call log: Hosts → Phone bridge → Call log → Grant.",
          ),
          BridgePermission(
              id = "call_phone",
              label = "Place calls",
              permission = Manifest.permission.CALL_PHONE,
              tools = "calls.dial",
              howTo = "Grant Phone: Hosts → Phone bridge → Place calls → Grant.",
          ),
          BridgePermission(
              id = "location",
              label = "Location",
              permission = Manifest.permission.ACCESS_FINE_LOCATION,
              tools = "location.current",
              howTo =
                  "Grant Location: Hosts → Phone bridge → Location → Grant, and choose " +
                      "\"Precise\" — a coarse grant answers with the wrong accuracy.",
          ),
          // The two Settings-granted rows. Neither is a runtime permission:
          // Android grants both only from their own Settings page, which is
          // why they carry an intent instead of a permission name.
          BridgePermission(
              id = NOTIFICATIONS,
              label = "Notification access",
              permission = null,
              tools = "notifications.list, reply, dismiss",
              howTo =
                  "Turn on notification access: Settings → Notifications → Device & app " +
                      "notifications → Vitruvian Remote.",
              settingsAction = Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS,
          ),
          BridgePermission(
              id = ACCESSIBILITY,
              label = "Screen control",
              permission = null,
              tools = "screen.tree, screenshot, tap, long_press, swipe, type, key",
              howTo = "Turn on the service: Settings → Accessibility → Vitruvian Remote → turn on.",
              settingsAction = Settings.ACTION_ACCESSIBILITY_SETTINGS,
          ),
      )

  /** The notification listener's row. Named because two files check it by id. */
  public const val NOTIFICATIONS: String = "notification_access"

  /** The accessibility service's row. */
  public const val ACCESSIBILITY: String = "accessibility"

  public fun byId(id: String): BridgePermission? = ROWS.firstOrNull { it.id == id }

  /**
   * Whether the phone has actually granted it.
   *
   * The two Settings-granted rows are asked of the SYSTEM -- the enabled-listener list and the
   * enabled-service list -- rather than of whether our own service object exists. The two differ
   * for several seconds after the switch is flipped, and a row that said "not granted" in that gap
   * would send someone back to a Settings page that is already correct.
   */
  public fun granted(context: Context, row: BridgePermission): Boolean =
      when (row.id) {
        NOTIFICATIONS -> BridgeNotificationListener.enabled(context)
        ACCESSIBILITY -> BridgeAccessibilityService.enabled(context)
        else -> {
          val name = row.permission
          name != null &&
              ContextCompat.checkSelfPermission(context, name) == PackageManager.PERMISSION_GRANTED
        }
      }

  /** The `isError` text a tool returns when [row]'s permission is missing. */
  public fun missing(row: BridgePermission): String =
      "${row.label} is not granted, so ${row.tools} cannot run. ${row.howTo}"
}

/** An outbound call waiting for a person to answer. */
public data class PendingApproval(
    val id: String,
    val tool: String,
    /** The question, already written out: "send SMS to +1… : 'text…'". */
    val question: String,
    val expiresAtMs: Long,
)

/**
 * Everything the bridge knows, shared by the service, the notification actions and the UI.
 *
 * A process-wide object rather than state passed around, because the three parties genuinely are in
 * three places: the link runs on the service's IO scope, Approve is a broadcast delivered to a
 * receiver, and the plate is drawn by an activity that may not have existed when the call arrived.
 * The alternative -- a bound service and three copies of the same trust deadline -- has a failure
 * mode this does not: two answers that disagree about whether agents are trusted.
 *
 * [attach] must be called before anything else; the service and the activity both do it, and it is
 * idempotent.
 */
public object BridgeHub {
  private val listeners = CopyOnWriteArrayList<() -> Unit>()
  private val waiting = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()

  @Volatile private var app: Context? = null
  @Volatile private var store: Persistence? = null

  /** Whether the outbound link to the Mac agent is up right now. */
  @Volatile
  public var linked: Boolean = false
    private set

  /** What the notification and the plate say about the link: "linked", "connecting…", a reason. */
  @Volatile
  public var linkStatus: String = "off"
    private set

  /** When the trust window shuts, epoch millis. 0 = never opened. */
  @Volatile
  public var trustUntil: Long = 0L
    private set

  @Volatile
  public var pending: PendingApproval? = null
    private set

  @Volatile
  public var audit: List<BridgeAuditEntry> = emptyList()
    private set

  public fun attach(context: Context) {
    if (app != null) return
    val application = context.applicationContext
    app = application
    val persistence = Persistence(application)
    store = persistence
    trustUntil = persistence.bridgeTrustUntil
    audit = persistence.bridgeAudit
    createChannels(application)
  }

  /** Whether the service should be running, as last chosen. */
  public fun enabled(): Boolean = store?.bridgeEnabled ?: false

  public fun setEnabled(value: Boolean) {
    store?.bridgeEnabled = value
    if (!value) {
      linked = false
      linkStatus = "off"
    }
    notifyListeners()
  }

  /** Called by the UI, so a plate can redraw when a call arrives while it is on screen. */
  public fun addListener(listener: () -> Unit) {
    listeners += listener
  }

  public fun removeListener(listener: () -> Unit) {
    listeners -= listener
  }

  internal fun setLink(up: Boolean, status: String) {
    linked = up
    linkStatus = status
    notifyListeners()
  }

  /** Opens the trust window for [millis] from now. Absolute, so re-opening does not stack. */
  public fun trustFor(millis: Long) {
    trustUntil = System.currentTimeMillis() + millis
    store?.bridgeTrustUntil = trustUntil
    record("trust", "for ${millis / 60_000} min", "window opened", "person")
    notifyListeners()
  }

  /** Shuts it early. The button that exists because an hour is a long time to change your mind. */
  public fun endTrust() {
    trustUntil = 0L
    store?.bridgeTrustUntil = 0L
    record("trust", "", "window closed", "person")
    notifyListeners()
  }

  public fun trustOpen(): Boolean = BridgePolicy.trustOpen(trustUntil, System.currentTimeMillis())

  public fun trustRemaining(): String =
      BridgePolicy.trustRemaining(trustUntil, System.currentTimeMillis())

  /** Adds one line to the audit trail and persists it. Newest first. */
  public fun record(tool: String, arguments: String, outcome: String, approver: String) {
    val entry =
        BridgeAuditEntry(
            atMs = System.currentTimeMillis(),
            tool = tool,
            arguments = arguments,
            outcome = outcome,
            approver = approver,
        )
    audit = (listOf(entry) + audit).take(BridgePolicy.AUDIT_LIMIT)
    store?.bridgeAudit = audit
    notifyListeners()
  }

  /**
   * Asks the person, and waits up to a minute.
   *
   * Two places to answer on purpose: the notification, because the phone is usually in a pocket and
   * not in this app, and the plate, because a notification that was swiped away would otherwise
   * leave the agent waiting out the whole minute with no way to say yes.
   *
   * Returns null when nobody answered, which the caller reports as "no answer in 60 s" rather than
   * as a refusal -- the difference matters to whoever reads the transcript afterwards.
   */
  public suspend fun awaitApproval(id: String, tool: String, question: String): Boolean? {
    val deferred = CompletableDeferred<Boolean>()
    waiting[id] = deferred
    pending =
        PendingApproval(
            id = id,
            tool = tool,
            question = question,
            expiresAtMs = System.currentTimeMillis() + BridgePolicy.APPROVAL_TIMEOUT_MS,
        )
    notifyListeners()
    postApprovalNotification(id, question)
    return try {
      withTimeoutOrNull(BridgePolicy.APPROVAL_TIMEOUT_MS) { deferred.await() }
    } finally {
      waiting.remove(id)
      if (pending?.id == id) pending = null
      cancelApprovalNotification()
      notifyListeners()
    }
  }

  /** Approve or Deny, from the notification action or from the plate. */
  public fun answer(id: String, approved: Boolean) {
    waiting.remove(id)?.complete(approved)
    if (pending?.id == id) pending = null
    cancelApprovalNotification()
    notifyListeners()
  }

  /** Answers whatever is pending. What the plate's two buttons call: it only ever shows one. */
  public fun answerPending(approved: Boolean) {
    pending?.let { answer(it.id, approved) }
  }

  private fun notifyListeners() {
    listeners.forEach { runCatching { it() } }
  }

  // --- notifications ----------------------------------------------------

  private fun createChannels(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val link = NotificationChannel(CHANNEL_LINK, "Phone bridge", NotificationManager.IMPORTANCE_LOW)
    link.description = "The link to the Mac, and how long agents stay trusted."
    // HIGH so it can appear over whatever is on screen: an approval that waits
    // silently in the shade is an approval nobody answers inside a minute.
    val approval =
        NotificationChannel(
            CHANNEL_APPROVAL, "Bridge approvals", NotificationManager.IMPORTANCE_HIGH)
    approval.description = "An agent asking to send a message or place a call."
    manager.createNotificationChannel(link)
    manager.createNotificationChannel(approval)
  }

  private fun postApprovalNotification(id: String, question: String) {
    val context = app ?: return
    val notification =
        NotificationCompat.Builder(context, CHANNEL_APPROVAL)
            .setSmallIcon(R.drawable.ic_tile_lock_mac)
            .setContentTitle("Agent wants to: $question")
            .setContentText("Approve within 60 seconds, or it is refused.")
            .setStyle(NotificationCompat.BigTextStyle().bigText(question))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .addAction(0, "Approve", answerIntent(context, id, true))
            .addAction(0, "Deny", answerIntent(context, id, false))
            .build()
    // Posting without POST_NOTIFICATIONS is a no-op rather than a crash, and
    // the plate still shows the same question -- which is why the prompt is in
    // two places.
    runCatching { NotificationManagerCompat.from(context).notify(APPROVAL_ID, notification) }
  }

  private fun cancelApprovalNotification() {
    val context = app ?: return
    runCatching { NotificationManagerCompat.from(context).cancel(APPROVAL_ID) }
  }

  private fun answerIntent(context: Context, id: String, approved: Boolean): PendingIntent {
    val intent =
        Intent(context, ApprovalReceiver::class.java)
            .setAction(
                if (approved) ApprovalReceiver.ACTION_APPROVE else ApprovalReceiver.ACTION_DENY)
            .putExtra(ApprovalReceiver.EXTRA_ID, id)
    return PendingIntent.getBroadcast(
        context,
        // Per call AND per answer, so Approve and Deny are two distinct
        // intents rather than one that the system reuses with the first
        // extras it ever saw.
        (id + approved).hashCode(),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  /** The service's own notification channel, so it can build the ongoing one. */
  public const val CHANNEL_LINK: String = "vitruvian-bridge"

  private const val CHANNEL_APPROVAL = "vitruvian-bridge-approval"
  private const val APPROVAL_ID = 0x8102
}
