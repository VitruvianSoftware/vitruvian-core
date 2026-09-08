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

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.PowerManager
import android.provider.CallLog
import android.provider.ContactsContract
import android.telephony.SmsManager
import dev.vitruvian.remote.state.BridgePolicy
import dev.vitruvian.remote.state.ToolDescriptor
import dev.vitruvian.remote.state.ToolTier
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

/**
 * What a tool answers with: the text of the one MCP content item, and whether it is an error.
 *
 * Always JSON in [text] for a success, so the agent on the Mac gets structure rather than prose it
 * has to parse; always a plain sentence for an error, because an error is read by a person.
 */
public data class ToolResult(val text: String, val isError: Boolean = false)

/**
 * One tool the phone offers.
 *
 * [call] blocks; the bridge runs it on an IO thread and its answer has 30 seconds to arrive (90 for
 * an outbound tool, which may be waiting on a tap). Everything a tool needs -- the `Context`, the
 * permission table -- is captured when it is built, so this interface stays four values and a
 * function and Part 2 can implement it against a notification listener or an accessibility service
 * without touching anything here.
 */
public interface PhoneTool {
  public val name: String
  public val description: String
  public val tier: ToolTier
  /** JSON Schema, as raw JSON text. */
  public val inputSchema: String

  public fun call(arguments: JSONObject): ToolResult
}

/**
 * The tools this phone announces, in the order they are registered.
 *
 * Extension point for Part 2: build the notification and screen tools with [tool] and hand them to
 * [register] before the service links. Nothing else needs to change -- the descriptor list, the
 * tier gate, the audit trail and the approval prompt all read from here.
 */
public class ToolRegistry {
  private val tools = LinkedHashMap<String, PhoneTool>()

  public fun register(tool: PhoneTool) {
    tools[tool.name] = tool
  }

  public fun registerAll(list: List<PhoneTool>) {
    list.forEach(::register)
  }

  public fun get(name: String): PhoneTool? = tools[name]

  public val names: List<String>
    get() = tools.keys.toList()

  /** What `POST /v1/phone/link` announces. */
  public fun descriptors(): List<ToolDescriptor> =
      tools.values.map { ToolDescriptor(it.name, it.description, it.inputSchema, it.tier) }
}

/**
 * Builds a tool, and appends the untrusted-input sentence to its description.
 *
 * Appended here rather than typed into each description because it is the one line that must be on
 * EVERY tool -- it is what tells the model on the Mac that a text message asking it to forward the
 * inbox is data, not an instruction -- and a sentence that has to be remembered nine times is a
 * sentence that will be missing from the tenth.
 */
public fun tool(
    name: String,
    tier: ToolTier,
    description: String,
    inputSchema: String = BridgePolicy.EMPTY_SCHEMA,
    handler: (JSONObject) -> ToolResult,
): PhoneTool =
    object : PhoneTool {
      override val name: String = name
      override val description: String = "$description ${BridgePolicy.UNTRUSTED}"
      override val tier: ToolTier = tier
      override val inputSchema: String = inputSchema

      override fun call(arguments: JSONObject): ToolResult = handler(arguments)
    }

/** The v1.3 slice's tools: status, SMS, contacts, calls, location and opening things. */
public object PhoneTools {

  /**
   * Everything this half of the bridge offers. Part 2 appends to the registry, not to this list.
   */
  public fun standard(context: Context): List<PhoneTool> =
      listOf(
          status(context),
          smsList(context),
          smsSend(context),
          contactsSearch(context),
          callsLog(context),
          callsDial(context),
          locationCurrent(context),
          appsOpen(context),
      )

  // --- phone.status -----------------------------------------------------

  private fun status(context: Context): PhoneTool =
      tool(
          name = "phone.status",
          tier = ToolTier.Read,
          description =
              "The phone itself: battery percent and whether it is charging, the network it is " +
                  "on, whether the screen is on, the ringer mode, and when the agent trust " +
                  "window closes.",
      ) {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val power = context.getSystemService(PowerManager::class.java)
        val audio = context.getSystemService(AudioManager::class.java)
        val json =
            JSONObject()
                .put(
                    "battery_percent",
                    if (level >= 0 && scale > 0) level * PERCENT / scale else JSONObject.NULL,
                )
                .put("charging", plugged != 0)
                .put("network", networkKind(context))
                .put("screen_on", power?.isInteractive ?: false)
                .put(
                    "ringer_mode",
                    when (audio?.ringerMode) {
                      AudioManager.RINGER_MODE_SILENT -> "silent"
                      AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                      AudioManager.RINGER_MODE_NORMAL -> "normal"
                      else -> "unknown"
                    },
                )
                // Null, not a past timestamp, when the window is shut: an
                // expired instant here reads to an agent as "trusted until
                // then" rather than "not trusted".
                .put(
                    "trust_until",
                    BridgePolicy.trustUntilIso(BridgeHub.trustUntil, System.currentTimeMillis())
                        ?: JSONObject.NULL,
                )
        ToolResult(json.toString())
      }

  /** What the phone is actually on, from the capabilities of the active network. */
  private fun networkKind(context: Context): String {
    val manager = context.getSystemService(ConnectivityManager::class.java) ?: return "unknown"
    val network = manager.activeNetwork ?: return "none"
    val caps = manager.getNetworkCapabilities(network) ?: return "none"
    return when {
      caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
      else -> "other"
    }
  }

  // --- sms.list ---------------------------------------------------------

  private fun smsList(context: Context): PhoneTool =
      tool(
          name = "sms.list",
          tier = ToolTier.Read,
          description =
              "The most recent received text messages, newest first, optionally only from one " +
                  "number.",
          inputSchema =
              """
              {"type":"object","properties":{
                "n":{"type":"integer","description":"How many, default 20, max 100"},
                "from":{"type":"string","description":"Only messages whose sender contains this"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        requirePermission(context, "read_sms")
            ?: run {
              val n = args.optInt("n", DEFAULT_ROWS).coerceIn(1, MAX_ROWS)
              val from = args.optString("from").trim()
              val selection = if (from.isBlank()) null else "address LIKE ?"
              val selectionArgs = if (from.isBlank()) null else arrayOf("%$from%")
              val rows = JSONArray()
              query(
                  context,
                  Uri.parse("content://sms/inbox"),
                  arrayOf("address", "body", "date"),
                  selection,
                  selectionArgs,
                  "date DESC",
              ) { cursor ->
                var count = 0
                while (count < n && cursor.moveToNext()) {
                  rows.put(
                      JSONObject()
                          .put("from", cursor.getString(0).orEmpty())
                          .put("body", cursor.getString(1).orEmpty())
                          .put("at", iso(cursor.getLong(2))))
                  count++
                }
              }
              ToolResult(JSONObject().put("messages", rows).put("count", rows.length()).toString())
            }
      }

  // --- sms.send ---------------------------------------------------------

  private fun smsSend(context: Context): PhoneTool =
      tool(
          name = "sms.send",
          tier = ToolTier.Outbound,
          description = "Sends a text message from this phone.",
          inputSchema =
              """
              {"type":"object","required":["to","body"],"properties":{
                "to":{"type":"string","description":"The phone number to text"},
                "body":{"type":"string","description":"The message"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val to = args.optString("to").trim()
        val body = args.optString("body")
        when {
          to.isBlank() || body.isBlank() ->
              ToolResult("\"to\" and \"body\" are both required", true)
          else ->
              requirePermission(context, "send_sms")
                  ?: runCatching {
                        val manager = smsManager(context)
                        // divideMessage + sendMultipart, always: a single-part
                        // send silently truncates anything over 160 characters,
                        // and the caller is told the message was sent.
                        val parts = manager.divideMessage(body)
                        manager.sendMultipartTextMessage(to, null, parts, null, null)
                        ToolResult(
                            JSONObject()
                                .put("sent", true)
                                .put("to", to)
                                .put("parts", parts.size)
                                .toString())
                      }
                      .getOrElse { ToolResult("could not send: ${it.message}", true) }
        }
      }

  private fun smsManager(context: Context): SmsManager =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        context.getSystemService(SmsManager::class.java)
      } else {
        @Suppress("DEPRECATION") SmsManager.getDefault()
      }

  // --- contacts.search --------------------------------------------------

  private fun contactsSearch(context: Context): PhoneTool =
      tool(
          name = "contacts.search",
          tier = ToolTier.Read,
          description =
              "Finds contacts whose name contains a string, with their numbers and " +
                  "email addresses.",
          inputSchema =
              """
              {"type":"object","required":["query"],"properties":{
                "query":{"type":"string","description":"Part of the contact's name"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val term = args.optString("query").trim()
        when {
          term.isBlank() -> ToolResult("\"query\" is required", true)
          else ->
              requirePermission(context, "read_contacts")
                  ?: run {
                    // One query over the Data table rather than one per
                    // contact: twenty contacts is forty round trips the other
                    // way, and every one of them is a Binder call.
                    val found = LinkedHashMap<Long, ContactRow>()
                    query(
                        context,
                        ContactsContract.Data.CONTENT_URI,
                        arrayOf(
                            ContactsContract.Data.CONTACT_ID,
                            ContactsContract.Data.DISPLAY_NAME,
                            ContactsContract.Data.MIMETYPE,
                            ContactsContract.Data.DATA1,
                        ),
                        "${ContactsContract.Data.DISPLAY_NAME} LIKE ? AND " +
                            "${ContactsContract.Data.MIMETYPE} IN (?,?)",
                        arrayOf(
                            "%$term%",
                            ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                            ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE,
                        ),
                        ContactsContract.Data.DISPLAY_NAME,
                    ) { cursor ->
                      while (cursor.moveToNext()) {
                        val id = cursor.getLong(0)
                        if (found.size >= MAX_CONTACTS && id !in found) break
                        val row = found.getOrPut(id) { ContactRow(cursor.getString(1).orEmpty()) }
                        val value = cursor.getString(3).orEmpty()
                        if (value.isBlank()) continue
                        if (cursor.getString(2) ==
                            ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE) {
                          if (value !in row.numbers) row.numbers += value
                        } else if (value !in row.emails) {
                          row.emails += value
                        }
                      }
                    }
                    val rows = JSONArray()
                    found.values.forEach { row ->
                      rows.put(
                          JSONObject()
                              .put("name", row.name)
                              .put("numbers", JSONArray(row.numbers))
                              .put("emails", JSONArray(row.emails)))
                    }
                    ToolResult(
                        JSONObject().put("contacts", rows).put("count", rows.length()).toString())
                  }
        }
      }

  private class ContactRow(
      val name: String,
      var numbers: List<String> = emptyList(),
      var emails: List<String> = emptyList(),
  )

  // --- calls.log --------------------------------------------------------

  private fun callsLog(context: Context): PhoneTool =
      tool(
          name = "calls.log",
          tier = ToolTier.Read,
          description = "The most recent calls, newest first, with direction and duration.",
          inputSchema =
              """
              {"type":"object","properties":{
                "n":{"type":"integer","description":"How many, default 20, max 100"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        requirePermission(context, "read_call_log")
            ?: run {
              val n = args.optInt("n", DEFAULT_ROWS).coerceIn(1, MAX_ROWS)
              val rows = JSONArray()
              query(
                  context,
                  CallLog.Calls.CONTENT_URI,
                  arrayOf(
                      CallLog.Calls.NUMBER,
                      CallLog.Calls.CACHED_NAME,
                      CallLog.Calls.TYPE,
                      CallLog.Calls.DATE,
                      CallLog.Calls.DURATION,
                  ),
                  null,
                  null,
                  "${CallLog.Calls.DATE} DESC",
              ) { cursor ->
                var count = 0
                while (count < n && cursor.moveToNext()) {
                  rows.put(
                      JSONObject()
                          .put("number", cursor.getString(0).orEmpty())
                          .put("name", cursor.getString(1).orEmpty())
                          .put("direction", callDirection(cursor.getInt(2)))
                          .put("at", iso(cursor.getLong(3)))
                          .put("duration_s", cursor.getLong(4)))
                  count++
                }
              }
              ToolResult(JSONObject().put("calls", rows).put("count", rows.length()).toString())
            }
      }

  private fun callDirection(type: Int): String =
      when (type) {
        CallLog.Calls.INCOMING_TYPE -> "incoming"
        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
        CallLog.Calls.MISSED_TYPE -> "missed"
        CallLog.Calls.REJECTED_TYPE -> "rejected"
        CallLog.Calls.BLOCKED_TYPE -> "blocked"
        CallLog.Calls.VOICEMAIL_TYPE -> "voicemail"
        else -> "other"
      }

  // --- calls.dial -------------------------------------------------------

  private fun callsDial(context: Context): PhoneTool =
      tool(
          name = "calls.dial",
          tier = ToolTier.Outbound,
          description = "Places a call from this phone.",
          inputSchema =
              """
              {"type":"object","required":["number"],"properties":{
                "number":{"type":"string","description":"The number to call"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val number = args.optString("number").trim()
        when {
          number.isBlank() -> ToolResult("\"number\" is required", true)
          else ->
              requirePermission(context, "call_phone")
                  ?: runCatching {
                        val intent =
                            Intent(Intent.ACTION_CALL, Uri.parse("tel:${Uri.encode(number)}"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        ToolResult(JSONObject().put("dialing", number).toString())
                      }
                      // From Android 10 a background activity start can be
                      // refused, and the honest answer is the refusal rather
                      // than a "dialing" that never rang. Unlocking the phone
                      // and trying again is what makes it work.
                      .getOrElse {
                        ToolResult(
                            "could not place the call: ${it.message}. Android refuses to start " +
                                "the dialer from the background on some phones; unlock the " +
                                "phone and try again.",
                            true,
                        )
                      }
        }
      }

  // --- location.current -------------------------------------------------

  private fun locationCurrent(context: Context): PhoneTool =
      tool(
          name = "location.current",
          tier = ToolTier.Read,
          description = "Where the phone is: latitude, longitude, accuracy and how old the fix is.",
      ) {
        requirePermission(context, "location")
            ?: run {
              val manager = context.getSystemService(LocationManager::class.java)
              if (manager == null) {
                ToolResult("this phone has no location service", true)
              } else {
                val fix = freshFix(manager) ?: lastKnown(manager)
                if (fix == null) {
                  ToolResult(
                      "no location fix within ${FIX_TIMEOUT_S} s and nothing stored. Turn " +
                          "Location on in the phone's quick settings, or move somewhere with " +
                          "a view of the sky, and try again.",
                      true,
                  )
                } else {
                  ToolResult(
                      JSONObject()
                          .put("lat", fix.latitude)
                          .put("lon", fix.longitude)
                          .put(
                              "accuracy_m",
                              if (fix.hasAccuracy()) fix.accuracy else JSONObject.NULL)
                          .put("age_s", (System.currentTimeMillis() - fix.time) / MS_PER_S)
                          .put("provider", fix.provider.orEmpty())
                          .toString())
                }
              }
            }
      }

  /** The newest stored fix from any provider, which may be hours old -- hence `age_s`. */
  private fun lastKnown(manager: LocationManager): Location? =
      runCatching {
            manager
                .getProviders(true)
                .mapNotNull { manager.getLastKnownLocation(it) }
                .maxByOrNull { it.time }
          }
          .getOrNull()

  /**
   * One fresh fix, or null after [FIX_TIMEOUT_S] seconds.
   *
   * Blocking on a latch because the whole tool is blocking: the bridge runs it on an IO thread and
   * the Mac agent is holding a call open. The listener is registered on the main looper because
   * `LocationManager` requires a prepared one, and an IO thread has none.
   */
  private fun freshFix(manager: LocationManager): Location? {
    val provider =
        when {
          manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
          manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
              LocationManager.NETWORK_PROVIDER
          else -> return null
        }
    val latch = CountDownLatch(1)
    var result: Location? = null
    val listener =
        object : LocationListener {
          override fun onLocationChanged(location: Location) {
            result = location
            latch.countDown()
          }

          // Present because the three-argument overloads are abstract below
          // API 30; without them this object does not compile against 26.
          @Deprecated("Deprecated in Java")
          override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?): Unit = Unit

          override fun onProviderEnabled(provider: String): Unit = Unit

          override fun onProviderDisabled(provider: String): Unit = Unit
        }
    return runCatching {
          manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
          latch.await(FIX_TIMEOUT_S, TimeUnit.SECONDS)
          manager.removeUpdates(listener)
          result
        }
        .getOrNull()
  }

  // --- apps.open --------------------------------------------------------

  private fun appsOpen(context: Context): PhoneTool =
      tool(
          name = "apps.open",
          tier = ToolTier.Act,
          description =
              "Opens an app by package name, or a link -- an http(s) URL or any app's own URI " +
                  "scheme.",
          inputSchema =
              """
              {"type":"object","required":["target"],"properties":{
                "target":{"type":"string","description":"A package name like com.spotify.music, or a URI like https://… or spotify:…"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val target = args.optString("target").trim()
        when {
          target.isBlank() -> ToolResult("\"target\" is required", true)
          target.contains("://") || (target.contains(':') && !target.contains('.')) ->
              openUri(context, target)
          else -> openPackage(context, target)
        }
      }

  private fun openUri(context: Context, target: String): ToolResult =
      runCatching {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(target))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            ToolResult(JSONObject().put("opened", target).toString())
          }
          .getOrElse { ToolResult("nothing on this phone opens $target: ${it.message}", true) }

  private fun openPackage(context: Context, target: String): ToolResult {
    val intent = context.packageManager.getLaunchIntentForPackage(target)
    if (intent == null) {
      return ToolResult(
          "$target is not installed, or has no launcher activity. Use apps.open with a URI, or " +
              "install the app on the phone first.",
          true,
      )
    }
    return runCatching {
          context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
          ToolResult(JSONObject().put("opened", target).toString())
        }
        .getOrElse { ToolResult("could not open $target: ${it.message}", true) }
  }

  // --- helpers ----------------------------------------------------------

  /**
   * The refusal for a missing permission, or null when it is granted.
   *
   * Null-as-success so a tool body reads `requirePermission(...) ?: run { … }`: the check cannot be
   * forgotten, because forgetting it means a SecurityException the agent sees as a stack trace
   * instead of the sentence that names the button.
   */
  private fun requirePermission(context: Context, id: String): ToolResult? {
    val row = BridgePermissions.byId(id) ?: return null
    if (BridgePermissions.granted(context, row)) return null
    return ToolResult(BridgePermissions.missing(row), true)
  }

  /**
   * Runs a content query, and treats every failure as an empty cursor.
   *
   * A provider can throw for reasons that are not a missing permission -- a work profile, a phone
   * with no messaging app at all -- and the caller has already checked the permission, so the
   * honest answer here is an empty list rather than a crash inside the bridge.
   */
  private fun query(
      context: Context,
      uri: Uri,
      projection: Array<String>,
      selection: String?,
      selectionArgs: Array<String>?,
      sortOrder: String?,
      read: (Cursor) -> Unit,
  ) {
    runCatching {
      context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use(read)
    }
  }

  private fun iso(epochMillis: Long): String =
      DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMillis))

  private const val DEFAULT_ROWS = 20
  private const val MAX_ROWS = 100
  private const val MAX_CONTACTS = 20
  private const val PERCENT = 100
  private const val MS_PER_S = 1000L
  private const val FIX_TIMEOUT_S = 10L
}
