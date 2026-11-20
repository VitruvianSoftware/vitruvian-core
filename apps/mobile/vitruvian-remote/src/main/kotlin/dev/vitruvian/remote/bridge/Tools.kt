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
import android.content.IntentFilter
import android.database.Cursor
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaDataSource
import android.media.MediaPlayer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.CallLog
import android.provider.ContactsContract
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.telephony.SmsManager
import android.util.Base64
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.texttospeech.SpeechSynthesis
import com.google.mlkit.genai.texttospeech.SpeechSynthesizer
import com.google.mlkit.genai.texttospeech.SpeechSynthesizerOptions
import com.google.mlkit.genai.texttospeech.SpeechSynthesizerRequest
import com.google.mlkit.genai.texttospeech.SpeechSynthesizerResponse
import com.google.mlkit.genai.texttospeech.VoiceInfo
import dev.vitruvian.remote.state.BridgePolicy
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.PhoneVoiceOption
import dev.vitruvian.remote.state.ToolDescriptor
import dev.vitruvian.remote.state.ToolTier
import dev.vitruvian.remote.state.readPhoneVoice
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

/**
 * What a tool answers with: the text of the one MCP content item, and whether it is an error.
 *
 * Always JSON in [text] for a success, so the agent on the Mac gets structure rather than prose it
 * has to parse; always a plain sentence for an error, because an error is read by a person.
 */
public data class ToolResult(
    val text: String,
    val isError: Boolean = false,
    /**
     * A picture, base64 with no line breaks, sent as a second MCP content item beside [text].
     *
     * Only `screen.screenshot` sets it. The text item stays mandatory even then, because that is
     * where the pixel size goes -- an agent handed a downscaled JPEG with no scale beside it will
     * tap where things are in the PICTURE rather than on the phone.
     */
    val imageBase64: String? = null,
    val imageMimeType: String = BridgePolicy.JPEG,
)

/**
 * One tool the phone offers.
 *
 * [call] blocks; the bridge runs it on an IO thread and its answer has 30 seconds to arrive (60–210
 * for `phone.speak`, 90 for an outbound tool, which may be waiting on a tap). Everything a tool
 * needs -- the `Context`, the permission table -- is captured when it is built, so this interface
 * stays four values and a function and Part 2 can implement it against a notification listener or
 * an accessibility service without touching anything here.
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
          speak(context),
          smsList(context),
          smsSend(context),
          contactsSearch(context),
          callsLog(context),
          callsDial(context),
          locationCurrent(context),
          appsOpen(context),
      )

  private val speakLock = Any()

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

  /** Opens a URI on the phone via [Intent.ACTION_VIEW]. */
  public fun openUrl(context: Context, target: String): Result<Unit> = runCatching {
    context.startActivity(
        Intent(Intent.ACTION_VIEW, Uri.parse(target)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  }

  private fun openUri(context: Context, target: String): ToolResult =
      openUrl(context, target)
          .map { ToolResult(JSONObject().put("opened", target).toString()) }
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

  // --- phone.speak ------------------------------------------------------

  /**
   * Speaks a Vitruvian Speaker announcement on the phone.
   *
   * Deliberately [ToolTier.Read] so unattended Vitruvian Speaker announcements from the Mac play
   * immediately when the user turns on "This phone" in Vitruvian Speaker settings, rather than
   * blocking on a 90-second interactive outbound approval prompt while the phone is in a pocket.
   */
  private fun speak(context: Context): PhoneTool =
      tool(
          name = "phone.speak",
          tier = ToolTier.Read,
          description =
              "Speaks a short announcement aloud on the phone, or plays a pre-synthesized WAV " +
                  "audio clip from Vitruvian Speaker on the Mac.",
          inputSchema =
              """
              {"type":"object","properties":{
                "text":{"type":"string","description":"The announcement text to speak via ML Kit GenAI TTS (with Android TextToSpeech fallback) when wav_base64 is absent"},
                "wav_base64":{"type":"string","description":"Optional base64-encoded WAV audio clip synthesized on the Mac (Gemini TTS)"},
                "pause_media":{"type":"boolean","description":"Whether to request transient audio focus so playing media pauses while speaking (default false)"},
                "headphones_only":{"type":"boolean","description":"Whether to skip speaking when no wired or Bluetooth headphones are connected (default false)"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        synchronized(speakLock) {
          val text = args.optString("text").trim()
          val wavBase64 = args.optString("wav_base64").trim()
          if (text.isBlank() && wavBase64.isBlank()) {
            return@synchronized ToolResult("either \"text\" or \"wav_base64\" is required", true)
          }
          val pauseMedia = args.optBoolean("pause_media", false)
          val headphonesOnly = args.optBoolean("headphones_only", false)
          val audio = context.getSystemService(AudioManager::class.java)
          if (headphonesOnly && !hasHeadphonesConnected(audio)) {
            return@synchronized skippedResult("no headphones connected")
          }
          val speechAttrs =
              AudioAttributes.Builder()
                  .setUsage(AudioAttributes.USAGE_MEDIA)
                  .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                  .build()
          if (wavBase64.isNotBlank()) {
            val wavOutcome =
                playWavBase64(context, audio, speechAttrs, wavBase64, pauseMedia, headphonesOnly)
            if (!wavOutcome.result.isError || !wavOutcome.allowTtsFallback || text.isBlank()) {
              wavOutcome.result
            } else {
              speakOnDeviceTts(context, audio, speechAttrs, text, pauseMedia, headphonesOnly)
            }
          } else {
            speakOnDeviceTts(context, audio, speechAttrs, text, pauseMedia, headphonesOnly)
          }
        }
      }

  private fun skippedResult(reason: String): ToolResult =
      ToolResult(
          JSONObject().put("spoken", false).put("skipped", true).put("reason", reason).toString())

  private fun hasHeadphonesConnected(audio: AudioManager?): Boolean =
      audio?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.any {
        Derive.isHeadphoneDeviceType(it.type)
      } ?: false

  private fun <T> withTransientAudioFocus(
      audio: AudioManager?,
      speechAttrs: AudioAttributes,
      pauseMedia: Boolean,
      block: () -> T,
  ): T {
    val focusRequest =
        if (pauseMedia && audio != null) {
          AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
              .setAudioAttributes(speechAttrs)
              .build()
              .also { audio.requestAudioFocus(it) }
        } else {
          null
        }
    return try {
      block()
    } finally {
      if (focusRequest != null && audio != null) {
        runCatching { audio.abandonAudioFocusRequest(focusRequest) }
      }
    }
  }

  private fun <T> withHeadphoneGuard(
      context: Context,
      audio: AudioManager?,
      headphonesOnly: Boolean,
      onUnplugged: () -> Unit,
      block: () -> T,
  ): T {
    if (!headphonesOnly || audio == null) return block()
    val deviceCallback =
        object : AudioDeviceCallback() {
          override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            if (!hasHeadphonesConnected(audio)) {
              onUnplugged()
            }
          }
        }
    val noisyReceiver =
        object : BroadcastReceiver() {
          override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
              onUnplugged()
            }
          }
        }
    audio.registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
    runCatching {
      context.registerReceiver(
          noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
    }
    return try {
      block()
    } finally {
      runCatching { audio.unregisterAudioDeviceCallback(deviceCallback) }
      runCatching { context.unregisterReceiver(noisyReceiver) }
    }
  }

  private data class WavPlayOutcome(
      val result: ToolResult,
      val allowTtsFallback: Boolean,
      /**
       * ML Kit failed before any audio in a way a new client can cure: the engine reported an error
       * or the client threw. The old client is already closed when this is set.
       */
      val freshClientMayHelp: Boolean = false,
  )

  private fun playWavBase64(
      context: Context,
      audio: AudioManager?,
      speechAttrs: AudioAttributes,
      wavBase64: String,
      pauseMedia: Boolean,
      headphonesOnly: Boolean,
  ): WavPlayOutcome {
    val rawBytes =
        runCatching { Base64.decode(wavBase64, Base64.DEFAULT) }.getOrNull()
            ?: return WavPlayOutcome(
                ToolResult("invalid wav_base64 payload", true),
                allowTtsFallback = true,
            )
    if (rawBytes.isEmpty()) {
      return WavPlayOutcome(
          ToolResult("invalid wav_base64 payload", true),
          allowTtsFallback = true,
      )
    }
    val bytes = BridgePolicy.prependWavSilence(rawBytes)
    val timeoutSeconds =
        BridgePolicy.speakTimeoutSeconds(BridgePolicy.wavDurationSeconds(bytes), textLength = 0)
    val player = MediaPlayer()
    val doneLatch = CountDownLatch(1)
    val unplugged = AtomicBoolean(false)
    val playError = AtomicReference<String?>(null)
    return try {
      player.setAudioAttributes(speechAttrs)
      player.setDataSource(
          object : MediaDataSource() {
            override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
              if (position >= bytes.size) return -1
              val available = (bytes.size - position).toInt()
              val toRead = minOf(size, available)
              System.arraycopy(bytes, position.toInt(), buffer, offset, toRead)
              return toRead
            }

            override fun getSize(): Long = bytes.size.toLong()

            override fun close(): Unit = Unit
          })
      player.setOnCompletionListener { doneLatch.countDown() }
      player.setOnErrorListener { _, what, extra ->
        playError.set("MediaPlayer error ($what, $extra)")
        doneLatch.countDown()
        true
      }
      player.prepare()
      withHeadphoneGuard(
          context,
          audio,
          headphonesOnly,
          onUnplugged = {
            unplugged.set(true)
            runCatching { if (player.isPlaying) player.stop() }
            doneLatch.countDown()
          }) {
            if (headphonesOnly && !hasHeadphonesConnected(audio)) {
              return@withHeadphoneGuard WavPlayOutcome(
                  skippedResult("no headphones connected"),
                  allowTtsFallback = false,
              )
            }
            withTransientAudioFocus(audio, speechAttrs, pauseMedia) {
              player.start()
              val finished = doneLatch.await(timeoutSeconds, TimeUnit.SECONDS)
              when {
                unplugged.get() ->
                    WavPlayOutcome(
                        skippedResult("headphones unplugged"),
                        allowTtsFallback = false,
                    )
                playError.get() != null ->
                    WavPlayOutcome(
                        ToolResult(playError.get()!!, true),
                        allowTtsFallback = true,
                    )
                !finished -> {
                  runCatching { if (player.isPlaying) player.stop() }
                  WavPlayOutcome(
                      ToolResult("WAV playback timed out after $timeoutSeconds s", true),
                      allowTtsFallback = false,
                  )
                }
                else ->
                    WavPlayOutcome(
                        ToolResult(
                            JSONObject().put("spoken", true).put("engine", "gemini").toString()),
                        allowTtsFallback = false,
                    )
              }
            }
          }
    } catch (e: Exception) {
      WavPlayOutcome(
          ToolResult("could not play WAV audio: ${e.message}", true),
          allowTtsFallback = true,
      )
    } finally {
      runCatching { player.release() }
    }
  }

  private val mlKitLock = Any()
  private var mlKitSynthesizer: SpeechSynthesizer? = null
  // The last voice lookup, so most announcements skip the per-voice status checks. Guarded by
  // mlKitLock; null voice means "no voice ready" (cached for a shorter time, see BridgePolicy).
  private var mlKitVoiceCache: MlKitVoiceCacheEntry? = null
  // Voice names downloading now. One set for both callers, so the picker's Get is never dropped
  // because an automatic download of another voice is running, and the same voice never starts
  // twice.
  private val mlKitDownloadsInFlight: MutableSet<String> =
      java.util.concurrent.ConcurrentHashMap.newKeySet()
  // Bumped whenever the cached voice is dropped; a lookup only writes the cache if no drop
  // happened while it ran, so a Use mid-lookup is never overwritten by the old answer.
  private val mlKitVoiceGeneration = dev.vitruvian.remote.state.GenerationGate()
  // The picked voice, in memory: read once from prefs, then set by the picker. Null until loaded.
  @Volatile private var mlKitPreferredVoice: String? = null
  private val mlKitDownloadScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  private data class MlKitVoiceCacheEntry(val voice: VoiceInfo?, val atMs: Long)

  /**
   * Releases the cached ML Kit [SpeechSynthesizer] Binder connection and forgets the cached voice.
   * Safe to call repeatedly when `PhoneBridgeService` stops or is destroyed.
   */
  public fun shutdownMlKitTts() {
    synchronized(mlKitLock) {
      runCatching { mlKitSynthesizer?.close() }
      mlKitSynthesizer = null
      mlKitVoiceCache = null
    }
  }

  /**
   * Closes the cached client so the next call builds a new one. Used after an answer that a dead
   * engine binding would produce (an error, an empty list). Callers that still hold the old client
   * see their call fail and retry once on the new one.
   */
  private fun discardMlKitClientIfStale() {
    shutdownMlKitTts()
  }

  /** Drops the cached voice, so the next announcement looks again. */
  public fun forgetMlKitVoice() {
    synchronized(mlKitLock) {
      mlKitVoiceGeneration.invalidate()
      mlKitVoiceCache = null
    }
  }

  /**
   * The pick changed: reload it from prefs (already written by the picker) and drop the cached
   * voice. Reading the saved value rather than taking it as an argument means two quick picks can
   * finish in either order and still leave the newest one in memory.
   */
  public fun reloadPreferredMlKitVoice(context: Context) {
    mlKitPreferredVoice = runCatching { readPhoneVoice(context) }.getOrDefault("")
    forgetMlKitVoice()
  }

  private suspend fun supportedMlKitVoices(synthesizer: SpeechSynthesizer): List<VoiceInfo> {
    val defaultLocale = Locale.getDefault()
    return synthesizer.getSupportedVoices(defaultLocale).ifEmpty {
      if (defaultLocale != Locale.US) synthesizer.getSupportedVoices(Locale.US) else emptyList()
    }
  }

  /** Every on-device voice for the phone's language, for the voice picker. Empty if unsupported. */
  public fun listMlKitVoices(): List<PhoneVoiceOption> {
    // An empty or failed answer can come from a client whose engine restarted, or one an
    // announcement just closed: try once more on a fresh client before showing "no voices".
    // The retry uses a private client: only announcements (under the speak lock) may close the
    // shared one, so opening the picker can never cut an announcement off.
    val first = listMlKitVoicesOnce(getOrCreateMlKitSynthesizer())
    if (first.isNotEmpty()) return first
    return withTemporaryMlKitClient { listMlKitVoicesOnce(it) }.orEmpty()
  }

  /** Runs [block] on a new client of its own and closes it after; null if one cannot be made. */
  private inline fun <R> withTemporaryMlKitClient(block: (SpeechSynthesizer) -> R): R? {
    val client = runCatching { newMlKitClient() }.getOrNull() ?: return null
    return try {
      block(client)
    } finally {
      runCatching { client.close() }
    }
  }

  private fun listMlKitVoicesOnce(synthesizer: SpeechSynthesizer): List<PhoneVoiceOption> =
      runCatching {
            runBlocking(Dispatchers.IO) {
              withTimeoutOrNull(MLKIT_LOOKUP_TIMEOUT_MS) {
                supportedMlKitVoices(synthesizer).map { voice ->
                  PhoneVoiceOption(
                      name = voice.name,
                      languageTag = voice.locale.toLanguageTag(),
                      gender =
                          when (voice.gender) {
                            VoiceInfo.Gender.FEMALE -> "female"
                            VoiceInfo.Gender.MALE -> "male"
                            else -> ""
                          },
                      status =
                          BridgePolicy.statusWithInFlight(
                              mapFeatureStatus(synthesizer.checkStatus(voice)),
                              voice.name,
                              mlKitDownloadsInFlight),
                  )
                }
              }
            }
          }
          .getOrNull()
          .orEmpty()

  /**
   * Downloads [name] because the user picked it: any network, since they asked for it. Runs off the
   * caller's thread entirely. True unless that voice is already downloading.
   */
  public fun downloadMlKitVoice(name: String): Boolean {
    if (!BridgePolicy.pickerShouldStartDownload(name, mlKitDownloadsInFlight)) return false
    // Registered before returning, so a list refresh right after Get already sees it downloading.
    if (!mlKitDownloadsInFlight.add(name)) return false
    mlKitDownloadScope.launch {
      try {
        // Twice at most: the second time on a fresh client, for when the first was closed under
        // us or lost its engine.
        suspend fun downloadOn(synthesizer: SpeechSynthesizer): Boolean =
            runCatching {
                  supportedMlKitVoices(synthesizer)
                      .firstOrNull { it.name == name }
                      ?.let { runVoiceDownload(synthesizer, it) }
                  true
                }
                .getOrDefault(false)
        if (downloadOn(getOrCreateMlKitSynthesizer())) return@launch
        // Second try on a private client, never closing the shared one an announcement may use.
        val client = runCatching { newMlKitClient() }.getOrNull() ?: return@launch
        try {
          downloadOn(client)
        } finally {
          runCatching { client.close() }
        }
        // The list shows it downloadable again; Get can be tapped again.
      } finally {
        mlKitDownloadsInFlight.remove(name)
      }
    }
    return true
  }

  /**
   * Plays a short sample in [name] for the picker. Null when it played, otherwise why not. Holds
   * the speak lock, so a sample and an announcement never talk over each other.
   */
  public fun previewMlKitVoice(context: Context, name: String): String? {
    // The lookup runs before taking the speak lock, so only the sample itself (a couple of
    // seconds, capped at PREVIEW_TIMEOUT_S) can make an announcement wait.
    val synthesizer =
        runCatching { getOrCreateMlKitSynthesizer() }
            .getOrElse {
              return "The sample did not play: ${it.message}"
            }
    val voice =
        runCatching {
              runBlocking(Dispatchers.IO) {
                withTimeoutOrNull(MLKIT_LOOKUP_TIMEOUT_MS) {
                  supportedMlKitVoices(synthesizer).firstOrNull { it.name == name }
                }
              }
            }
            .getOrNull() ?: return "That voice is not on this phone any more"
    return synchronized(speakLock) {
      try {
        val attrs =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        // The same playback path announcements use, so a sample sounds and behaves exactly like
        // the real thing (start window, stop handling).
        val outcome =
            speakMlKitTts(
                context,
                context.getSystemService(AudioManager::class.java),
                attrs,
                PREVIEW_TEXT,
                pauseMedia = true,
                headphonesOnly = false,
                timeoutSeconds = PREVIEW_TIMEOUT_S,
                voiceOverride = voice,
            )
        if (outcome.result.isError) "The sample did not play: ${outcome.result.text}" else null
      } catch (t: Throwable) {
        "The sample did not play: ${t.message}"
      }
    }
  }

  // ML Kit initializes itself at app start through the MlKitInitProvider its AAR merges into our
  // manifest (checked in the built APK), so no internal init call is needed here.
  private fun newMlKitClient(): SpeechSynthesizer =
      SpeechSynthesis.getClient(
          SpeechSynthesizerOptions.builder(Locale.getDefault())
              .setVoiceFallbackEnabled(false)
              .build())

  private fun getOrCreateMlKitSynthesizer(): SpeechSynthesizer =
      synchronized(mlKitLock) {
        mlKitSynthesizer ?: newMlKitClient().also { mlKitSynthesizer = it }
      }

  /**
   * The voice picked in Phone Bridge settings; empty means automatic. Read from prefs once without
   * building a [Persistence] (whose migrations must not race the activity's), then kept in memory.
   */
  private fun preferredVoice(context: Context): String =
      mlKitPreferredVoice
          ?: runCatching { readPhoneVoice(context) }
              .getOrDefault("")
              .also { mlKitPreferredVoice = it }

  /** Unmetered by the underlying network, so Tailscale's VPN does not hide home Wi-Fi. */
  private fun isUnmetered(context: Context): Boolean =
      context.getSystemService(ConnectivityManager::class.java)?.let { !it.isActiveNetworkMetered }
          ?: false

  private fun startBackgroundVoiceDownload(synthesizer: SpeechSynthesizer, voice: VoiceInfo) {
    if (!mlKitDownloadsInFlight.add(voice.name)) return
    mlKitDownloadScope.launch {
      try {
        runVoiceDownload(synthesizer, voice)
      } catch (_: Throwable) {
        // Best effort: the next lookup on Wi-Fi tries again.
      } finally {
        mlKitDownloadsInFlight.remove(voice.name)
      }
    }
  }

  /** Downloads [voice] to the end; the caller owns the in-flight entry. */
  private suspend fun runVoiceDownload(synthesizer: SpeechSynthesizer, voice: VoiceInfo) {
    synthesizer.download(voice).collect { status ->
      if (status is DownloadStatus.DownloadCompleted) forgetMlKitVoice()
    }
  }

  private fun mapFeatureStatus(status: Int): BridgePolicy.MlKitVoiceStatus =
      when (status) {
        FeatureStatus.AVAILABLE -> BridgePolicy.MlKitVoiceStatus.Available
        FeatureStatus.DOWNLOADABLE -> BridgePolicy.MlKitVoiceStatus.Downloadable
        FeatureStatus.DOWNLOADING -> BridgePolicy.MlKitVoiceStatus.Downloading
        else -> BridgePolicy.MlKitVoiceStatus.Unavailable
      }

  /** A ready voice from the cache, or a fresh lookup; null when none is ready to speak now. */
  /** A voice lookup's answer; [staleClient] means the client looked dead (closed, not cached). */
  private data class VoiceLookup(val voice: VoiceInfo?, val staleClient: Boolean = false)

  private fun readyMlKitVoice(context: Context, synthesizer: SpeechSynthesizer): VoiceLookup {
    val now = System.currentTimeMillis()
    val generation = mlKitVoiceGeneration.begin()
    synchronized(mlKitLock) {
      mlKitVoiceCache?.let { cached ->
        if (BridgePolicy.mlKitVoiceCacheFresh(now - cached.atMs, ready = cached.voice != null)) {
          return VoiceLookup(cached.voice)
        }
      }
    }
    var voiceCount = -1
    val lookup =
        runBlocking(Dispatchers.IO) {
          withTimeoutOrNull(MLKIT_LOOKUP_TIMEOUT_MS) {
            val voices = supportedMlKitVoices(synthesizer)
            voiceCount = voices.size
            val candidates =
                voices.map { voice ->
                  BridgePolicy.MlKitVoiceCandidate(
                      name = voice.name,
                      languageTag = voice.locale.toLanguageTag(),
                      status = mapFeatureStatus(synthesizer.checkStatus(voice)),
                  )
                }
            val selection = BridgePolicy.selectMlKitVoice(candidates, preferredVoice(context))
            if (BridgePolicy.shouldDownloadMlKitVoice(
                selection, isUnmetered(context), mlKitDownloadsInFlight.isNotEmpty())) {
              val name = (selection as BridgePolicy.MlKitVoiceSelection.NeedsDownload).name
              voices
                  .firstOrNull { it.name == name }
                  ?.let { startBackgroundVoiceDownload(synthesizer, it) }
            }
            // Wrapped, so "no ready voice" (null inside) differs from "timed out" (null outside).
            VoiceLookup(
                (selection as? BridgePolicy.MlKitVoiceSelection.Ready)?.let { ready ->
                  voices.firstOrNull { it.name == ready.name }
                })
          }
        }
    val sharedCount = if (lookup == null) BridgePolicy.VOICES_NO_ANSWER else voiceCount
    // No voices (or no answer) is either a lost engine or a phone with none for its language. Ask
    // a brand-new client to tell them apart: it is bound to the engine as it is now.
    val probeCount =
        if (BridgePolicy.needsStaleProbe(sharedCount)) {
          withTemporaryMlKitClient { probe ->
            runBlocking(Dispatchers.IO) {
              withTimeoutOrNull(MLKIT_LOOKUP_TIMEOUT_MS) { supportedMlKitVoices(probe).size }
            }
          } ?: BridgePolicy.VOICES_NO_ANSWER
        } else {
          sharedCount
        }
    if (BridgePolicy.sharedClientIsStale(sharedCount, probeCount)) {
      // A new client sees voices ours cannot: ours lost its engine. Close it and leave the cache
      // alone, so the announcement retries on a new client instead of sticking on "not ready".
      discardMlKitClientIfStale()
      return VoiceLookup(null, staleClient = true)
    }
    val voice = lookup?.voice
    synchronized(mlKitLock) {
      // A Use (or a finished download) during the lookup bumped the generation: this answer may
      // be stale, so leave the cache empty and let the next announcement look again.
      if (mlKitVoiceGeneration.stillCurrent(generation)) {
        mlKitVoiceCache = MlKitVoiceCacheEntry(voice, now)
      }
    }
    return VoiceLookup(voice)
  }

  /**
   * Speaks on-device by preferring ML Kit GenAI TTS (backed by `com.google.android.tts`) and
   * falling back to Android's platform `TextToSpeech` only when nothing was heard yet, inside one
   * time budget for the whole call.
   */
  private fun speakOnDeviceTts(
      context: Context,
      audio: AudioManager?,
      speechAttrs: AudioAttributes,
      text: String,
      pauseMedia: Boolean,
      headphonesOnly: Boolean,
  ): ToolResult {
    val budgetSeconds =
        BridgePolicy.speakTimeoutSeconds(wavDurationSeconds = null, textLength = text.length)
    val startNs = System.nanoTime()
    // When Google's speech app updates or restarts, the client we hold keeps pointing at the old
    // engine ("not bound to TTS engine") and fails at once, every time. One retry on a new
    // client, inside the same budget, reconnects instead of falling back for good.
    val mlKitOutcome =
        BridgePolicy.speakWithFreshClientRetry(
            budgetSeconds = budgetSeconds,
            textLength = text.length,
            elapsedSeconds = { TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - startNs) },
            describe = { outcome: WavPlayOutcome ->
              BridgePolicy.mlKitAttemptOf(
                  isError = outcome.result.isError,
                  allowFallback = outcome.allowTtsFallback,
                  freshClientMayHelp = outcome.freshClientMayHelp,
              )
            },
            onRetry = { outcome ->
              Log.i(TTS_LOG_TAG, "mlkit: retrying on a new client after: ${outcome.result.text}")
            },
        ) { remainingSeconds ->
          speakMlKitTts(
              context, audio, speechAttrs, text, pauseMedia, headphonesOnly, remainingSeconds)
        }
    if (!mlKitOutcome.result.isError || !mlKitOutcome.allowTtsFallback) {
      return mlKitOutcome.result
    }
    val elapsedSeconds = TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - startNs)
    val remaining =
        BridgePolicy.fallbackTimeoutSeconds(budgetSeconds, elapsedSeconds, text.length)
            ?: return ToolResult(
                "${mlKitOutcome.result.text}; too little time left for the Android voice", true)
    return speakTts(context, audio, speechAttrs, text, pauseMedia, headphonesOnly, remaining)
  }

  private fun speakMlKitTts(
      context: Context,
      audio: AudioManager?,
      speechAttrs: AudioAttributes,
      text: String,
      pauseMedia: Boolean,
      headphonesOnly: Boolean,
      timeoutSeconds: Long,
      voiceOverride: VoiceInfo? = null,
  ): WavPlayOutcome {
    fun fallback(reason: String) = WavPlayOutcome(ToolResult(reason, true), allowTtsFallback = true)
    // The budget counts from here, so the voice lookup (and a stale-client probe) is inside it.
    val callStartNs = System.nanoTime()
    // Outside the try, so a throw mid-sentence still knows audio was heard.
    val started = AtomicBoolean(false)
    return try {
      val synthesizer = getOrCreateMlKitSynthesizer()
      val voice =
          voiceOverride
              ?: readyMlKitVoice(context, synthesizer).let { lookup ->
                lookup.voice
                    ?: return WavPlayOutcome(
                        ToolResult(
                            if (lookup.staleClient) "ML Kit TTS lost its engine"
                            else "ML Kit TTS voice not ready",
                            true),
                        allowTtsFallback = true,
                        freshClientMayHelp = lookup.staleClient,
                    )
              }

      val unplugged = AtomicBoolean(false)
      val end = AtomicReference<BridgePolicy.MlKitEnd?>(null)
      val errorCode = AtomicReference<Int?>(null)
      withHeadphoneGuard(
          context,
          audio,
          headphonesOnly,
          onUnplugged = {
            unplugged.set(true)
            runCatching { synthesizer.stop() }
          }) {
            if (headphonesOnly && !hasHeadphonesConnected(audio)) {
              return@withHeadphoneGuard WavPlayOutcome(
                  skippedResult("no headphones connected"),
                  allowTtsFallback = false,
              )
            }
            withTransientAudioFocus(audio, speechAttrs, pauseMedia) {
              if (pauseMedia || headphonesOnly) {
                runCatching { Thread.sleep(BridgePolicy.WAV_PREROLL_MS.toLong()) }
              }
              val request =
                  SpeechSynthesizerRequest(
                      SpeechSynthesizerRequest.Input.Text(text, voice),
                      speechAttrs,
                      TextToSpeech.QUEUE_FLUSH,
                  )
              runBlocking(Dispatchers.IO) {
                val startSignal = CompletableDeferred<Unit>()
                val job = launch {
                  synthesizer
                      .synthesize(request)
                      .takeWhile { response ->
                        if (response !is SpeechSynthesizerResponse.AudioAvailable ||
                            !started.get()) {
                          // Kinds only, never the announcement text.
                          Log.d(
                              TTS_LOG_TAG,
                              "mlkit: ${response.javaClass.simpleName} ${(response as? SpeechSynthesizerResponse.StatusUpdate)?.status ?: ""}")
                        }
                        when (response) {
                          is SpeechSynthesizerResponse.Error -> {
                            errorCode.set(response.errorCode)
                            end.compareAndSet(null, BridgePolicy.MlKitEnd.Error)
                            false
                          }
                          is SpeechSynthesizerResponse.StatusUpdate ->
                              when (response.status) {
                                SpeechSynthesizerResponse.Status.START -> {
                                  started.set(true)
                                  startSignal.complete(Unit)
                                  true
                                }
                                SpeechSynthesizerResponse.Status.DONE -> {
                                  end.compareAndSet(null, BridgePolicy.MlKitEnd.Done)
                                  false
                                }
                                SpeechSynthesizerResponse.Status.STOP -> {
                                  end.compareAndSet(null, BridgePolicy.MlKitEnd.Stopped)
                                  false
                                }
                              }
                          is SpeechSynthesizerResponse.AudioAvailable -> {
                            started.set(true)
                            startSignal.complete(Unit)
                            !unplugged.get()
                          }
                        }
                      }
                      .collect {}
                  // The flow can also just end; without a DONE that is an early stop.
                  end.compareAndSet(null, BridgePolicy.MlKitEnd.Stopped)
                }
                // Phase 1: give ML Kit a short window to start, so a stuck engine leaves the
                // Android voice most of the budget. Phase 2: let it finish within the budget.
                val startedOrEnded =
                    withTimeoutOrNull(BridgePolicy.MLKIT_START_TIMEOUT_MS) {
                      select<Unit> {
                        startSignal.onAwait {}
                        job.onJoin {}
                      }
                    } != null
                val finished =
                    startedOrEnded &&
                        withTimeoutOrNull(
                            BridgePolicy.mlKitFinishWindowMs(
                                timeoutSeconds,
                                TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - callStartNs))) {
                              job.join()
                            } != null
                if (!finished) {
                  end.compareAndSet(
                      null,
                      if (started.get()) BridgePolicy.MlKitEnd.Timeout
                      else BridgePolicy.MlKitEnd.StartTimeout)
                  job.cancel()
                  runCatching { synthesizer.stop() }
                }
              }
              val outcome =
                  BridgePolicy.classifyMlKitEnd(
                      end.get() ?: BridgePolicy.MlKitEnd.Stopped, started.get(), unplugged.get())
              Log.i(TTS_LOG_TAG, "mlkit: end=${end.get()} started=${started.get()} -> $outcome")
              when (outcome) {
                BridgePolicy.MlKitOutcome.Spoken ->
                    WavPlayOutcome(
                        ToolResult(
                            JSONObject().put("spoken", true).put("engine", "mlkit_tts").toString()),
                        allowTtsFallback = false,
                    )
                BridgePolicy.MlKitOutcome.Unplugged ->
                    WavPlayOutcome(skippedResult("headphones unplugged"), allowTtsFallback = false)
                is BridgePolicy.MlKitOutcome.Partial ->
                    // Not an error: something was spoken, and nothing upstream should retry it.
                    WavPlayOutcome(
                        ToolResult(
                            JSONObject()
                                .put("spoken", true)
                                .put("partial", true)
                                .put("engine", "mlkit_tts")
                                .put("reason", withCode(outcome.reason, errorCode.get()))
                                .toString()),
                        allowTtsFallback = false,
                    )
                is BridgePolicy.MlKitOutcome.Fallback -> {
                  val engineError = end.get() == BridgePolicy.MlKitEnd.Error
                  // An engine error can mean our client lost its engine (the speech app updated
                  // or restarted). Close it, so the next attempt builds a new, bound one.
                  if (engineError) shutdownMlKitTts()
                  WavPlayOutcome(
                      ToolResult(withCode(outcome.reason, errorCode.get()), true),
                      allowTtsFallback = true,
                      freshClientMayHelp = engineError,
                  )
                }
              }
            }
          }
    } catch (t: Throwable) {
      shutdownMlKitTts()
      if (BridgePolicy.afterClientThrow(started.get()) == BridgePolicy.AfterThrow.ReportPartial) {
        // Some of it was heard: never retry or fall back, or the start would be said twice.
        WavPlayOutcome(
            ToolResult(
                JSONObject()
                    .put("spoken", true)
                    .put("partial", true)
                    .put("engine", "mlkit_tts")
                    .put("reason", "ML Kit TTS stopped partway through: ${t.message}")
                    .toString()),
            allowTtsFallback = false,
        )
      } else {
        WavPlayOutcome(
            ToolResult("could not speak via ML Kit TTS: ${t.message}", true),
            allowTtsFallback = true,
            freshClientMayHelp = true,
        )
      }
    }
  }

  private fun withCode(reason: String, code: Int?): String =
      if (code == null) reason else "$reason ($code)"

  private fun speakTts(
      context: Context,
      audio: AudioManager?,
      speechAttrs: AudioAttributes,
      text: String,
      pauseMedia: Boolean,
      headphonesOnly: Boolean,
      timeoutSeconds: Long =
          BridgePolicy.speakTimeoutSeconds(wavDurationSeconds = null, textLength = text.length),
  ): ToolResult {
    val initLatch = CountDownLatch(1)
    val initStatus = AtomicInteger(TextToSpeech.ERROR)
    val doneLatch = CountDownLatch(1)
    val unplugged = AtomicBoolean(false)
    val ttsError = AtomicReference<String?>(null)
    val engineRef = AtomicReference<TextToSpeech?>(null)
    val engine =
        TextToSpeech(context.applicationContext) { status ->
          initStatus.set(status)
          initLatch.countDown()
        }
    engineRef.set(engine)
    return try {
      if (!initLatch.await(TTS_INIT_TIMEOUT_S, TimeUnit.SECONDS) ||
          initStatus.get() != TextToSpeech.SUCCESS) {
        return ToolResult("Android TextToSpeech could not initialize", true)
      }
      engine.setAudioAttributes(speechAttrs)
      engine.setOnUtteranceProgressListener(
          object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?): Unit = Unit

            override fun onDone(utteranceId: String?) {
              doneLatch.countDown()
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
              ttsError.set("Android TextToSpeech failed")
              doneLatch.countDown()
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
              ttsError.set("Android TextToSpeech failed ($errorCode)")
              doneLatch.countDown()
            }
          })
      withHeadphoneGuard(
          context,
          audio,
          headphonesOnly,
          onUnplugged = {
            unplugged.set(true)
            runCatching { engineRef.get()?.stop() }
            doneLatch.countDown()
          }) {
            if (headphonesOnly && !hasHeadphonesConnected(audio)) {
              return@withHeadphoneGuard skippedResult("no headphones connected")
            }
            withTransientAudioFocus(audio, speechAttrs, pauseMedia) {
              if (pauseMedia || headphonesOnly) {
                runCatching { Thread.sleep(BridgePolicy.WAV_PREROLL_MS.toLong()) }
              }
              val utteranceId = "speaker-${System.currentTimeMillis()}"
              if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId) !=
                  TextToSpeech.SUCCESS) {
                return@withTransientAudioFocus ToolResult(
                    "Android TextToSpeech refused to queue speech", true)
              }
              val finished = doneLatch.await(timeoutSeconds, TimeUnit.SECONDS)
              when {
                unplugged.get() -> skippedResult("headphones unplugged")
                ttsError.get() != null -> ToolResult(ttsError.get()!!, true)
                !finished ->
                    ToolResult("Android TextToSpeech timed out after $timeoutSeconds s", true)
                else ->
                    ToolResult(
                        JSONObject().put("spoken", true).put("engine", "android_tts").toString())
              }
            }
          }
    } catch (e: Exception) {
      ToolResult("could not speak via Android TextToSpeech: ${e.message}", true)
    } finally {
      runCatching { engine.stop() }
      runCatching { engine.shutdown() }
    }
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
  private const val TTS_INIT_TIMEOUT_S = 10L
  private const val MLKIT_LOOKUP_TIMEOUT_MS = 5_000L
  private const val PREVIEW_TIMEOUT_S = 15L
  private const val TTS_LOG_TAG = "VitruvianTts"
  private const val PREVIEW_TEXT = "This is how your announcements will sound."
}
