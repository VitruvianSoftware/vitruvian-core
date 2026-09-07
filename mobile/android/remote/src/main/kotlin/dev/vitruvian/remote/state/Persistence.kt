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

package dev.vitruvian.remote.state

import android.content.Context
import android.content.SharedPreferences
import dev.vitruvian.remote.trackpad.TrackpadTuning

private const val PREFS = "vitruvian-remote"
private const val KEY_INSTALLED = "installed"
private const val KEY_HIDDEN = "hiddenWidgets"
private const val KEY_MACROS = "userMacros"
private const val KEY_THEME = "darkTheme"
private const val KEY_DOCK = "dockOpen"
private const val KEY_HOST = "selectedHost"
private const val KEY_POINTER_SPEED = "pointerSpeed"
private const val KEY_SCROLL_SPEED = "scrollSpeed"
private const val KEY_DRAG_HOLD = "dragHoldMillis"
private const val KEY_AGENT_URL = "agentUrl"
private const val KEY_AGENT_TOKEN = "agentToken"
private const val KEY_AGENT_MAC = "agentMac"
private const val KEY_HOST_ALIAS = "hostAlias"
private const val KEY_RECENT_COMMANDS = "recentCommands"

/** How many console commands are remembered. Beyond this the oldest fall off. */
private const val RECENT_COMMAND_LIMIT = 20

/** ASCII unit separator - the field delimiter inside one stored macro. */
private const val FIELD = "\u001F"

/** ASCII record separator - the delimiter between stored macros. */
private const val RECORD = "\u001E"

/**
 * The handful of things that survive a restart: installed modules, user macros, hidden widgets, the
 * selected host, the theme, the dock and how the trackpad feels.
 *
 * Deliberately `SharedPreferences` and not DataStore - this is five scalars and two small lists,
 * read once at startup and written on user action, so the flow machinery would be all cost and no
 * benefit.
 */
public class Persistence(context: Context) {
  private val prefs: SharedPreferences =
      context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  public var installed: List<String>
    get() = prefs.getStringSet(KEY_INSTALLED, null)?.toList() ?: MockHost.defaultInstalled.toList()
    set(value) = prefs.edit().putStringSet(KEY_INSTALLED, value.toSet()).apply()

  public var hiddenWidgets: List<String>
    get() = prefs.getStringSet(KEY_HIDDEN, emptySet())?.toList() ?: emptyList()
    set(value) = prefs.edit().putStringSet(KEY_HIDDEN, value.toSet()).apply()

  public var darkTheme: Boolean
    get() = prefs.getBoolean(KEY_THEME, true)
    set(value) = prefs.edit().putBoolean(KEY_THEME, value).apply()

  public var dockOpen: Boolean
    get() = prefs.getBoolean(KEY_DOCK, true)
    set(value) = prefs.edit().putBoolean(KEY_DOCK, value).apply()

  public var selectedHost: Int
    get() = prefs.getInt(KEY_HOST, 0)
    set(value) = prefs.edit().putInt(KEY_HOST, value).apply()

  /** Where the Mac agent is. Blank means "none": the dashboards stay simulated. */
  public var agentUrl: String
    get() = prefs.getString(KEY_AGENT_URL, "").orEmpty()
    set(value) = prefs.edit().putString(KEY_AGENT_URL, value.trim()).apply()

  /**
   * The bearer token pairing issued. Blank means this phone may read but not act.
   *
   * In plain `SharedPreferences` rather than the keystore, matching what it protects: the agent's
   * own copy sits in a 0600 file in the user's home directory, and the token only means anything to
   * someone already inside the tailnet. Worth revisiting if the agent ever leaves it.
   */
  public var agentToken: String
    get() = prefs.getString(KEY_AGENT_TOKEN, "").orEmpty()
    set(value) = prefs.edit().putString(KEY_AGENT_TOKEN, value.trim()).apply()

  /**
   * The Mac's en0 MAC address, learned from `GET /v1/host`.
   *
   * Persisted precisely because it is needed when the agent is NOT answering: a Wake-on-LAN packet
   * has to be addressed to a machine that is asleep, which is the one time it cannot tell us its
   * own address.
   */
  public var agentMac: String
    get() = prefs.getString(KEY_AGENT_MAC, "").orEmpty()
    set(value) = prefs.edit().putString(KEY_AGENT_MAC, value.trim()).apply()

  /**
   * What the user calls this Mac.
   *
   * Blank means "no name given", and the screens fall back to the hostname the Mac reports.
   * `James-MacBook-Pro` is a name Apple invented from an Apple ID, it is long, and every caption
   * that shows it uppercases it -- a two-word alias is worth a preference.
   */
  public var hostAlias: String
    get() = prefs.getString(KEY_HOST_ALIAS, "").orEmpty()
    set(value) = prefs.edit().putString(KEY_HOST_ALIAS, value.trim()).apply()

  /** The last [RECENT_COMMAND_LIMIT] console commands, newest first. */
  public var recentCommands: List<String>
    get() =
        prefs.getString(KEY_RECENT_COMMANDS, "").orEmpty().split(RECORD).filter { it.isNotBlank() }
    set(value) =
        prefs
            .edit()
            .putString(KEY_RECENT_COMMANDS, value.take(RECENT_COMMAND_LIMIT).joinToString(RECORD))
            .apply()

  /**
   * Trackpad feel.
   *
   * Clamped on the way OUT, not just on the way in. A value that is only validated when written
   * trusts every past version of this app and anyone with a rooted phone and a text editor; a
   * stored 0 here would give a pointer that never moves, which on screen is indistinguishable from
   * a Bluetooth link that never connected.
   */
  public var trackpadTuning: TrackpadTuning
    get() =
        TrackpadTuning(
            pointerPercent =
                TrackpadTuning.clampPercent(
                    prefs.getInt(KEY_POINTER_SPEED, TrackpadTuning.DEFAULT_PERCENT)),
            scrollPercent =
                TrackpadTuning.clampPercent(
                    prefs.getInt(KEY_SCROLL_SPEED, TrackpadTuning.DEFAULT_PERCENT)),
            dragHoldMillis =
                TrackpadTuning.clampDragHold(
                    prefs.getInt(KEY_DRAG_HOLD, TrackpadTuning.DEFAULT_DRAG_HOLD_MILLIS)),
        )
    set(value) =
        prefs
            .edit()
            .putInt(KEY_POINTER_SPEED, TrackpadTuning.clampPercent(value.pointerPercent))
            .putInt(KEY_SCROLL_SPEED, TrackpadTuning.clampPercent(value.scrollPercent))
            .putInt(KEY_DRAG_HOLD, TrackpadTuning.clampDragHold(value.dragHoldMillis))
            .apply()

  /**
   * Macros are stored as separator-delimited records.
   *
   * The separators are ASCII control characters precisely so that a macro's own label or shell
   * command - which can contain any printable character, including every plausible punctuation
   * delimiter - can never collide with them.
   */
  public var userMacros: List<Macro>
    get() =
        prefs
            .getString(KEY_MACROS, "")
            .orEmpty()
            .split(RECORD)
            .filter { it.isNotBlank() }
            .mapNotNull { record ->
              val parts = record.split(FIELD)
              if (parts.size < FIELD_COUNT) return@mapNotNull null
              Macro(
                  id = parts[0],
                  label = parts[1],
                  command = parts[2],
                  kind = runCatching { MacroKind.valueOf(parts[3]) }.getOrNull() ?: MacroKind.Ssh,
                  confirm = parts[4].toBooleanStrictOrNull() ?: false,
              )
            }
    set(value) {
      val encoded =
          value.joinToString(RECORD) { macro ->
            listOf(
                    macro.id,
                    macro.label,
                    macro.command,
                    macro.kind.name,
                    macro.confirm.toString(),
                )
                .joinToString(FIELD)
          }
      prefs.edit().putString(KEY_MACROS, encoded).apply()
    }

  private companion object {
    const val FIELD_COUNT = 5
  }
}
