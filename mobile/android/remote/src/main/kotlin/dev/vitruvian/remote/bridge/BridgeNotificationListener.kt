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
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import dev.vitruvian.remote.state.ToolTier
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONArray
import org.json.JSONObject

/**
 * The phone's notification shade, as three tools.
 *
 * A `NotificationListenerService` is bound by the SYSTEM, not by this app: it starts when the user
 * turns it on in Settings and it outlives the bridge's own service. So the active notifications are
 * kept in a process-wide map here rather than on the bridge, and the tools read that map -- which
 * also means `notifications.list` answers instantly instead of waiting for a bind that may not
 * happen while the phone is dozing.
 *
 * [connected] is the honest flag: the class existing proves nothing, because Android instantiates
 * the service only after the user has granted notification access.
 */
public class BridgeNotificationListener : NotificationListenerService() {

  override fun onListenerConnected() {
    super.onListenerConnected()
    instance = this
    connected = true
    // The map starts empty on every bind -- including a rebind after the
    // system killed us -- so seed it from what is on the phone right now.
    // Without this, notifications.list is empty until the next one arrives,
    // which reads as "nothing in the shade" rather than "not caught up yet".
    runCatching { activeNotifications }
        .getOrNull()
        ?.let { current ->
          active.clear()
          current.forEach { active[it.key] = it }
        }
  }

  override fun onListenerDisconnected() {
    connected = false
    if (instance === this) instance = null
    super.onListenerDisconnected()
  }

  override fun onNotificationPosted(sbn: StatusBarNotification?) {
    sbn ?: return
    active[sbn.key] = sbn
  }

  override fun onNotificationRemoved(sbn: StatusBarNotification?) {
    sbn ?: return
    active.remove(sbn.key)
  }

  override fun onDestroy() {
    connected = false
    if (instance === this) instance = null
    super.onDestroy()
  }

  public companion object {
    /** Everything in the shade, newest write wins, keyed the way Android keys it. */
    internal val active: ConcurrentHashMap<String, StatusBarNotification> = ConcurrentHashMap()

    /** The bound service, or null. `cancelNotification` is an instance method, hence this. */
    @Volatile internal var instance: BridgeNotificationListener? = null

    /** Whether the system has actually bound us. */
    @Volatile
    public var connected: Boolean = false
      private set

    /**
     * Whether the user has turned notification access on.
     *
     * Asked of the system rather than of [connected], because the two differ for a whole minute
     * after the switch is flipped: access is granted, the bind has not happened yet, and a row that
     * said "not granted" would send the user back to a Settings screen that is already correct.
     */
    public fun enabled(context: Context): Boolean =
        runCatching {
              NotificationManagerCompat.getEnabledListenerPackages(context)
                  .contains(context.packageName)
            }
            .getOrDefault(false)
  }
}

/** `notifications.list`, `notifications.reply` and `notifications.dismiss`. */
public object NotificationTools {

  public fun all(context: Context): List<PhoneTool> =
      listOf(list(context), reply(context), dismiss(context))

  // --- notifications.list -----------------------------------------------

  private fun list(context: Context): PhoneTool =
      tool(
          name = "notifications.list",
          tier = ToolTier.Read,
          description =
              "What is in the phone's notification shade right now: the app, the title and text, " +
                  "when it arrived, and whether it can be replied to.",
          inputSchema =
              """
              {"type":"object","properties":{
                "app":{"type":"string","description":"Only notifications whose package or app name contains this"},
                "n":{"type":"integer","description":"How many, newest first, default 30, max 100"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        requireAccess(context)
            ?: run {
              val n = args.optInt("n", DEFAULT_ROWS).coerceIn(1, MAX_ROWS)
              val filter = args.optString("app").trim().lowercase()
              val rows = JSONArray()
              snapshot(context)
                  .asSequence()
                  .filter { it.sbn.packageName != context.packageName }
                  .filter { row ->
                    filter.isBlank() ||
                        row.sbn.packageName.lowercase().contains(filter) ||
                        row.label.lowercase().contains(filter)
                  }
                  .sortedByDescending { it.sbn.postTime }
                  .take(n)
                  .forEach { rows.put(describe(it)) }
              ToolResult(
                  JSONObject().put("notifications", rows).put("count", rows.length()).toString())
            }
      }

  /**
   * The shade, newest first, with each app's readable name resolved once.
   *
   * A snapshot rather than a live view: the map is written from the system's binder thread while
   * this is being read, and a notification that vanishes halfway through the loop would otherwise
   * appear in the answer with half its fields.
   */
  private fun snapshot(context: Context): List<Row> {
    val labels = HashMap<String, String>()
    return BridgeNotificationListener.active.values.map { sbn ->
      Row(sbn, labels.getOrPut(sbn.packageName) { appLabel(context, sbn.packageName) })
    }
  }

  private class Row(val sbn: StatusBarNotification, val label: String)

  private fun describe(row: Row): JSONObject {
    val notification = row.sbn.notification
    val extras: Bundle = notification.extras ?: Bundle()
    val json =
        JSONObject()
            .put("key", row.sbn.key)
            .put("package", row.sbn.packageName)
            .put("app", row.label)
            .put("title", charSequence(extras, Notification.EXTRA_TITLE))
            .put("text", bodyText(notification, extras))
            .put("when", iso(row.sbn.postTime))
            .put("can_reply", replyAction(notification) != null)
            .put("ongoing", row.sbn.isOngoing)
    // Only when there is one: an empty array on every plain notification is
    // noise on a screen the agent reads thirty of at a time.
    messages(notification)?.let { json.put("messages", it) }
    return json
  }

  /**
   * The body: the big text when there is one, otherwise the collapsed line.
   *
   * EXTRA_BIG_TEXT first because a two-line email preview truncated to EXTRA_TEXT is exactly the
   * part an agent was asked to summarise.
   */
  private fun bodyText(notification: Notification, extras: Bundle): String {
    val big = charSequence(extras, Notification.EXTRA_BIG_TEXT)
    if (big.isNotBlank()) return big
    val text = charSequence(extras, Notification.EXTRA_TEXT)
    if (text.isNotBlank()) return text
    return charSequence(extras, Notification.EXTRA_SUB_TEXT)
  }

  /**
   * A messaging notification's individual messages, when it is one.
   *
   * Without this a chat notification's `text` is only the LAST line, and an agent asked "what did
   * Sam say" answers with the newest message as though it were the whole conversation.
   */
  private fun messages(notification: Notification): JSONArray? {
    val style =
        runCatching {
              NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(notification)
            }
            .getOrNull() ?: return null
    val messages = style.messages
    if (messages.isEmpty()) return null
    val array = JSONArray()
    messages.takeLast(MAX_MESSAGES).forEach { message ->
      array.put(
          JSONObject()
              .put("from", message.person?.name?.toString().orEmpty())
              .put("text", message.text?.toString().orEmpty())
              .put("at", iso(message.timestamp)))
    }
    return array
  }

  // --- notifications.reply ----------------------------------------------

  private fun reply(context: Context): PhoneTool =
      tool(
          name = "notifications.reply",
          tier = ToolTier.Outbound,
          description =
              "Replies to a notification through its own reply action -- the same box the phone " +
                  "shows when you swipe down and type. Use the key from notifications.list.",
          inputSchema =
              """
              {"type":"object","required":["key","text"],"properties":{
                "key":{"type":"string","description":"The notification's key, from notifications.list"},
                "text":{"type":"string","description":"What to send"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val key = args.optString("key").trim()
        val text = args.optString("text")
        when {
          key.isBlank() || text.isBlank() ->
              ToolResult("\"key\" and \"text\" are both required", true)
          else -> requireAccess(context) ?: send(context, key, text)
        }
      }

  private fun send(context: Context, key: String, text: String): ToolResult {
    val sbn =
        BridgeNotificationListener.active[key]
            ?: return ToolResult(
                "no notification with key $key is in the shade any more. It was dismissed or " +
                    "replaced; call notifications.list again for the current keys.",
                true,
            )
    val action =
        replyAction(sbn.notification)
            ?: return ToolResult(
                "the notification from ${sbn.packageName} has no reply action, so there is " +
                    "nothing to reply through. Open the app instead: apps.open " +
                    "${sbn.packageName}.",
                true,
            )
    val inputs =
        action.remoteInputs ?: return ToolResult("that notification has no reply box", true)
    return runCatching {
          val intent = Intent()
          val values = Bundle()
          // Every input, not just the first: some apps declare a second one
          // (a subject, a choice) and RemoteInput drops the whole send when a
          // declared key is missing from the results bundle.
          inputs.forEach { values.putCharSequence(it.resultKey, text) }
          RemoteInput.addResultsToIntent(inputs, intent, values)
          // Says the text was typed rather than picked from a suggestion.
          // Some messaging apps read this to decide whether to send straight
          // away or open their own compose screen with the text in it.
          if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            RemoteInput.setResultsSource(intent, RemoteInput.SOURCE_FREE_FORM_INPUT)
          }
          action.actionIntent.send(context, 0, intent)
          ToolResult(
              JSONObject()
                  .put("replied", true)
                  .put("key", key)
                  .put("app", sbn.packageName)
                  .toString())
        }
        .getOrElse {
          ToolResult(
              "the reply could not be delivered: ${it.message}. The app may have been stopped " +
                  "since the notification was posted.",
              true,
          )
        }
  }

  /** The first action with a text box on it. A "Mark as read" action has none, and is skipped. */
  private fun replyAction(notification: Notification): Notification.Action? =
      notification.actions?.firstOrNull { action ->
        action.remoteInputs?.any { it.allowFreeFormInput } == true && action.actionIntent != null
      }

  // --- notifications.dismiss --------------------------------------------

  private fun dismiss(context: Context): PhoneTool =
      tool(
          name = "notifications.dismiss",
          tier = ToolTier.Act,
          description =
              "Clears one notification from the shade. Use the key from notifications.list.",
          inputSchema =
              """
              {"type":"object","required":["key"],"properties":{
                "key":{"type":"string","description":"The notification's key, from notifications.list"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val key = args.optString("key").trim()
        when {
          key.isBlank() -> ToolResult("\"key\" is required", true)
          else ->
              requireAccess(context)
                  ?: run {
                    val service =
                        BridgeNotificationListener.instance
                            ?: return@run ToolResult(NOT_BOUND, true)
                    runCatching {
                          service.cancelNotification(key)
                          BridgeNotificationListener.active.remove(key)
                          ToolResult(JSONObject().put("dismissed", key).toString())
                        }
                        .getOrElse { ToolResult("could not dismiss $key: ${it.message}", true) }
                  }
        }
      }

  // --- helpers ----------------------------------------------------------

  /**
   * The refusal when notification access is off, or null when it is on.
   *
   * Two different refusals on purpose: access not granted names the Settings path, and access
   * granted but not yet bound says to wait -- sending someone to a switch that is already on is the
   * most annoying possible error message.
   */
  private fun requireAccess(context: Context): ToolResult? {
    val row = BridgePermissions.byId(BridgePermissions.NOTIFICATIONS) ?: return null
    if (!BridgeNotificationListener.enabled(context)) {
      return ToolResult(BridgePermissions.missing(row), true)
    }
    if (!BridgeNotificationListener.connected) return ToolResult(NOT_BOUND, true)
    return null
  }

  private fun appLabel(context: Context, packageName: String): String =
      runCatching {
            val manager = context.packageManager
            manager.getApplicationLabel(manager.getApplicationInfo(packageName, 0)).toString()
          }
          .getOrDefault(packageName)

  private fun charSequence(extras: Bundle, key: String): String =
      runCatching { extras.getCharSequence(key)?.toString().orEmpty() }.getOrDefault("")

  private fun iso(epochMillis: Long): String =
      DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMillis))

  private const val NOT_BOUND =
      "notification access is granted but Android has not connected the listener yet. It " +
          "usually takes a few seconds after the switch; if it does not, turn Vitruvian Remote " +
          "off and on again under Settings → Notifications → Device & app notifications."

  private const val DEFAULT_ROWS = 30
  private const val MAX_ROWS = 100
  private const val MAX_MESSAGES = 20
}
