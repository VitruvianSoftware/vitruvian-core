// Copyright (c) 2026 VitruvianSoftware

package dev.vitruvian.wand.core

/**
 * Pure Kotlin models and zero-dependency JSON parser/serializer for `wand_core` types:
 * - [WandAction] (`#[serde(tag = "type", content = "value", rename_all = "snake_case")]`)
 * - [WandConfig], [WandSettings], and [WandBinding]
 * - [WandSample] and [Vec3f]
 *
 * Default bindings are owned exclusively by `wand_core` in Rust and retrieved via
 * [WandNative.nativeDefaultConfig]; Kotlin never defines its own default bindings map.
 */
sealed class WandAction {
  data object LeftClick : WandAction()

  data object RightClick : WandAction()

  data object MouseDown : WandAction()

  data object MouseUp : WandAction()

  data class Scroll(val dx: Float, val dy: Float) : WandAction()

  data class Media(val kind: MediaKind) : WandAction()

  data class Volume(val kind: VolumeKind) : WandAction()

  data class Brightness(val kind: BrightnessKind) : WandAction()

  data class Key(
      val key: String,
      val ctrl: Boolean = false,
      val alt: Boolean = false,
      val shift: Boolean = false,
      val meta: Boolean = false,
  ) : WandAction()

  data class System(val kind: SystemKind) : WandAction()

  data object ToggleGyro : WandAction()

  data class LaunchApp(val packageName: String) : WandAction()

  data object RadialMenu : WandAction()

  data class Nav(val kind: NavKind) : WandAction()

  data class DPad(val direction: DPadDirection) : WandAction()

  data object ScreenOff : WandAction()

  data object Assistant : WandAction()

  data object VoiceTyping : WandAction()

  data class Move(val dx: Float, val dy: Float) : WandAction()

  fun displayLabel(): String =
      when (this) {
        LeftClick -> "Tap / Click"
        RightClick -> "Secondary Click"
        MouseDown -> "Mouse Down"
        MouseUp -> "Mouse Up"
        is Scroll ->
            when {
              dy > 0f -> "Scroll Up"
              dy < 0f -> "Scroll Down"
              dx > 0f -> "Scroll Right"
              dx < 0f -> "Scroll Left"
              else -> "Scroll"
            }
        is Media -> "Media: ${kind.label}"
        is Volume -> "Volume: ${kind.label}"
        is Brightness -> "Brightness: ${kind.label}"
        is Key -> "Key: $key"
        is System -> "System: ${kind.label}"
        ToggleGyro -> "Toggle Gyro Mode"
        is LaunchApp -> if (packageName.isBlank()) "Launch App" else "Launch: $packageName"
        RadialMenu -> "Radial Menu"
        is Nav -> "Nav: ${kind.label}"
        is DPad -> "D-Pad: ${direction.label}"
        ScreenOff -> "Screen Off (Lock)"
        Assistant -> "Assistant"
        VoiceTyping -> "Voice Typing"
        is Move -> "Move ($dx, $dy)"
      }
}

enum class MediaKind(val wire: String, val label: String) {
  PLAY_PAUSE("play_pause", "Play / Pause"),
  NEXT("next", "Next Track"),
  PREVIOUS("previous", "Previous Track"),
  ;

  companion object {
    fun fromWire(value: String): MediaKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class VolumeKind(val wire: String, val label: String) {
  UP("up", "Volume Up"),
  DOWN("down", "Volume Down"),
  MUTE("mute", "Mute"),
  ;

  companion object {
    fun fromWire(value: String): VolumeKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class BrightnessKind(val wire: String, val label: String) {
  UP("up", "Brightness Up"),
  DOWN("down", "Brightness Down"),
  ;

  companion object {
    fun fromWire(value: String): BrightnessKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class SystemKind(val wire: String, val label: String) {
  COPY("copy", "Copy"),
  PASTE("paste", "Paste"),
  CUT("cut", "Cut"),
  UNDO("undo", "Undo"),
  APP_SWITCHER("app_switcher", "App Switcher"),
  MISSION_CONTROL("mission_control", "Mission Control"),
  SHOW_DESKTOP("show_desktop", "Show Desktop"),
  ;

  companion object {
    fun fromWire(value: String): SystemKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class NavKind(val wire: String, val label: String) {
  BACK("back", "Back"),
  HOME("home", "Home"),
  RECENTS("recents", "Recents"),
  NOTIFICATIONS("notifications", "Notifications"),
  QUICK_SETTINGS("quick_settings", "Quick Settings"),
  ;

  companion object {
    fun fromWire(value: String): NavKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class DPadDirection(val wire: String, val label: String) {
  UP("up", "Up"),
  DOWN("down", "Down"),
  LEFT("left", "Left"),
  RIGHT("right", "Right"),
  CENTER("center", "Center / Select"),
  ;

  companion object {
    fun fromWire(value: String): DPadDirection? = entries.firstOrNull { it.wire == value }
  }
}

enum class WandButton(val wire: String, val label: String) {
  CLICK("click", "Touchpad Click"),
  APP("app", "App Button"),
  HOME("home", "Home Button"),
  VOL_UP("vol_up", "Volume Up"),
  VOL_DOWN("vol_down", "Volume Down"),
  TAP("tap", "Touchpad Tap"),
}

enum class WandPress(val wire: String, val label: String) {
  SHORT("short", "Short Press"),
  LONG("long", "Long Press"),
  DOUBLE("double", "Double Press"),
}

enum class WandTriggerMode(val wire: String, val label: String) {
  ONCE("once", "Once"),
  HOLD("hold", "Hold"),
  TOGGLE("toggle", "Toggle"),
  ;

  companion object {
    fun fromWire(value: String): WandTriggerMode = entries.firstOrNull { it.wire == value } ?: ONCE
  }
}

data class WandBinding(
    val action: WandAction,
    val trigger: WandTriggerMode = WandTriggerMode.ONCE,
)

data class WandSettings(
    val touchSensitivity: Float = 400.0f,
    val gyroXSpeed: Float = 18.0f,
    val gyroYSpeed: Float = 18.0f,
    val gyroDeadzone: Float = 0.03f,
    val touchDeadzone: Float = 0.005f,
    val accelerationCurve: Float = 1.0f,
    val emaSmoothing: Float = 0.3f,
    val reverseScroll: Boolean = false,
    val scrollStrength: Float = 1.0f,
    val horizontalScroll: Boolean = false,
    val tapInTouchMode: Boolean = true,
    val tapInGyroMode: Boolean = true,
    val autoReconnect: Boolean = true,
    val longPressMs: Long = 500L,
    val doublePressMs: Long = 300L,
    val radialDeadRadius: Float = 15.0f,
    val overlayCursor: Boolean = true,
    val overlayCursorSize: Float = 24.0f,
)

data class WandConfig(
    val version: Int = 1,
    val platform: String = "android",
    val settings: WandSettings = WandSettings(),
    val bindings: Map<String, WandBinding> = emptyMap(),
) {
  fun bindingFor(button: WandButton, press: WandPress): WandBinding? =
      bindings["${button.wire}.${press.wire}"]

  fun withBinding(button: WandButton, press: WandPress, binding: WandBinding?): WandConfig {
    val updated = bindings.toMutableMap()
    val key = "${button.wire}.${press.wire}"
    if (binding == null) {
      updated.remove(key)
    } else {
      updated[key] = binding
    }
    return copy(bindings = updated)
  }
}

data class Vec3f(
    val x: Float = 0f,
    val y: Float = 0f,
    val z: Float = 0f,
)

data class WandSample(
    val time: Int = 0,
    val seq: Int = 0,
    val orientation: Vec3f = Vec3f(),
    val accel: Vec3f = Vec3f(),
    val gyro: Vec3f = Vec3f(),
    val touchX: Float = 0f,
    val touchY: Float = 0f,
    val touching: Boolean = false,
    val click: Boolean = false,
    val home: Boolean = false,
    val app: Boolean = false,
    val volDown: Boolean = false,
    val volUp: Boolean = false,
)

/** Result of parsing a JSON response returned from `WandNative`. */
sealed class WandJsonResult<out T> {
  data class Ok<T>(val value: T) : WandJsonResult<T>()

  data class Error(val message: String) : WandJsonResult<Nothing>()
}

/** Pure Kotlin JSON parser and serializer for `wand-core` structures. */
object WandJson {
  fun parseActions(json: String): WandJsonResult<List<WandAction>> {
    val trimmed = json.trim()
    if (trimmed.isEmpty()) {
      return WandJsonResult.Error("empty JSON response")
    }
    return try {
      val root = MiniJsonParser(trimmed).parseValue()
      if (root is JsonVal.Obj) {
        val err = root.string("error")
        if (err != null) {
          return WandJsonResult.Error(err)
        }
        return WandJsonResult.Error("expected JSON array of actions, got object")
      }
      val arr =
          root as? JsonVal.Arr ?: return WandJsonResult.Error("expected JSON array of actions")
      val actions =
          arr.items.map { item ->
            val obj =
                item as? JsonVal.Obj
                    ?: throw IllegalArgumentException("action item must be a JSON object")
            parseActionObject(obj)
          }
      WandJsonResult.Ok(actions)
    } catch (e: Exception) {
      WandJsonResult.Error(e.message ?: "invalid actions JSON")
    }
  }

  fun parseAction(json: String): WandAction {
    val obj =
        MiniJsonParser(json.trim()).parseValue() as? JsonVal.Obj
            ?: throw IllegalArgumentException("action must be a JSON object")
    return parseActionObject(obj)
  }

  internal fun parseActionObject(obj: JsonVal.Obj): WandAction {
    val type =
        obj.string("type") ?: throw IllegalArgumentException("missing 'type' field in Action")
    val value = obj.fields["value"]
    return when (type) {
      "left_click" -> WandAction.LeftClick
      "right_click" -> WandAction.RightClick
      "mouse_down" -> WandAction.MouseDown
      "mouse_up" -> WandAction.MouseUp
      "toggle_gyro" -> WandAction.ToggleGyro
      "radial_menu" -> WandAction.RadialMenu
      "screen_off" -> WandAction.ScreenOff
      "assistant" -> WandAction.Assistant
      "voice_typing" -> WandAction.VoiceTyping
      "scroll" -> {
        val v =
            value as? JsonVal.Obj
                ?: throw IllegalArgumentException("scroll value must be an object")
        WandAction.Scroll(
            dx = v.float("dx") ?: 0f,
            dy = v.float("dy") ?: 0f,
        )
      }
      "move" -> {
        val v =
            value as? JsonVal.Obj ?: throw IllegalArgumentException("move value must be an object")
        WandAction.Move(
            dx = v.float("dx") ?: 0f,
            dy = v.float("dy") ?: 0f,
        )
      }
      "media" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("media value must be a string")
        val kind =
            MediaKind.fromWire(s) ?: throw IllegalArgumentException("unknown media action '$s'")
        WandAction.Media(kind)
      }
      "volume" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("volume value must be a string")
        val kind =
            VolumeKind.fromWire(s) ?: throw IllegalArgumentException("unknown volume action '$s'")
        WandAction.Volume(kind)
      }
      "brightness" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("brightness value must be a string")
        val kind =
            BrightnessKind.fromWire(s)
                ?: throw IllegalArgumentException("unknown brightness action '$s'")
        WandAction.Brightness(kind)
      }
      "key" -> {
        val v =
            value as? JsonVal.Obj ?: throw IllegalArgumentException("key value must be an object")
        WandAction.Key(
            key = v.string("key") ?: "",
            ctrl = v.bool("ctrl") ?: false,
            alt = v.bool("alt") ?: false,
            shift = v.bool("shift") ?: false,
            meta = v.bool("meta") ?: false,
        )
      }
      "system" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("system value must be a string")
        val kind =
            SystemKind.fromWire(s) ?: throw IllegalArgumentException("unknown system action '$s'")
        WandAction.System(kind)
      }
      "launch_app" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("launch_app value must be a string")
        WandAction.LaunchApp(s)
      }
      "nav" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("nav value must be a string")
        val kind = NavKind.fromWire(s) ?: throw IllegalArgumentException("unknown nav action '$s'")
        WandAction.Nav(kind)
      }
      "d_pad" -> {
        val s =
            (value as? JsonVal.Str)?.value
                ?: throw IllegalArgumentException("d_pad value must be a string")
        val dir =
            DPadDirection.fromWire(s)
                ?: throw IllegalArgumentException("unknown d_pad direction '$s'")
        WandAction.DPad(dir)
      }
      else -> throw IllegalArgumentException("unknown action type '$type'")
    }
  }

  fun serializeAction(action: WandAction): String =
      when (action) {
        WandAction.LeftClick -> """{"type":"left_click"}"""
        WandAction.RightClick -> """{"type":"right_click"}"""
        WandAction.MouseDown -> """{"type":"mouse_down"}"""
        WandAction.MouseUp -> """{"type":"mouse_up"}"""
        WandAction.ToggleGyro -> """{"type":"toggle_gyro"}"""
        WandAction.RadialMenu -> """{"type":"radial_menu"}"""
        WandAction.ScreenOff -> """{"type":"screen_off"}"""
        WandAction.Assistant -> """{"type":"assistant"}"""
        WandAction.VoiceTyping -> """{"type":"voice_typing"}"""
        is WandAction.Scroll ->
            """{"type":"scroll","value":{"dx":${action.dx},"dy":${action.dy}}}"""
        is WandAction.Move -> """{"type":"move","value":{"dx":${action.dx},"dy":${action.dy}}}"""
        is WandAction.Media -> """{"type":"media","value":${quote(action.kind.wire)}}"""
        is WandAction.Volume -> """{"type":"volume","value":${quote(action.kind.wire)}}"""
        is WandAction.Brightness -> """{"type":"brightness","value":${quote(action.kind.wire)}}"""
        is WandAction.Key ->
            """{"type":"key","value":{"key":${quote(action.key)},"ctrl":${action.ctrl},"alt":${action.alt},"shift":${action.shift},"meta":${action.meta}}}"""
        is WandAction.System -> """{"type":"system","value":${quote(action.kind.wire)}}"""
        is WandAction.LaunchApp -> """{"type":"launch_app","value":${quote(action.packageName)}}"""
        is WandAction.Nav -> """{"type":"nav","value":${quote(action.kind.wire)}}"""
        is WandAction.DPad -> """{"type":"d_pad","value":${quote(action.direction.wire)}}"""
      }

  fun parseConfig(json: String): WandJsonResult<WandConfig> {
    val trimmed = json.trim()
    if (trimmed.isEmpty()) {
      return WandJsonResult.Error("empty config JSON")
    }
    return try {
      val obj =
          MiniJsonParser(trimmed).parseValue() as? JsonVal.Obj
              ?: return WandJsonResult.Error("config must be a JSON object")
      val err = obj.string("error")
      if (err != null) {
        return WandJsonResult.Error(err)
      }
      val version = obj.int("version") ?: 1
      val platform = obj.string("platform") ?: "android"
      val sObj = obj.obj("settings")
      val defaults = WandSettings()
      val settings =
          if (sObj != null) {
            WandSettings(
                touchSensitivity = sObj.float("touch_sensitivity") ?: defaults.touchSensitivity,
                gyroXSpeed = sObj.float("gyro_x_speed") ?: defaults.gyroXSpeed,
                gyroYSpeed = sObj.float("gyro_y_speed") ?: defaults.gyroYSpeed,
                gyroDeadzone = sObj.float("gyro_deadzone") ?: defaults.gyroDeadzone,
                touchDeadzone = sObj.float("touch_deadzone") ?: defaults.touchDeadzone,
                accelerationCurve = sObj.float("acceleration_curve") ?: defaults.accelerationCurve,
                emaSmoothing = sObj.float("ema_smoothing") ?: defaults.emaSmoothing,
                reverseScroll = sObj.bool("reverse_scroll") ?: defaults.reverseScroll,
                scrollStrength = sObj.float("scroll_strength") ?: defaults.scrollStrength,
                horizontalScroll = sObj.bool("horizontal_scroll") ?: defaults.horizontalScroll,
                tapInTouchMode = sObj.bool("tap_in_touch_mode") ?: defaults.tapInTouchMode,
                tapInGyroMode = sObj.bool("tap_in_gyro_mode") ?: defaults.tapInGyroMode,
                autoReconnect = sObj.bool("auto_reconnect") ?: defaults.autoReconnect,
                longPressMs = sObj.long("long_press_ms") ?: defaults.longPressMs,
                doublePressMs = sObj.long("double_press_ms") ?: defaults.doublePressMs,
                radialDeadRadius = sObj.float("radial_dead_radius") ?: defaults.radialDeadRadius,
                overlayCursor = sObj.bool("overlay_cursor") ?: defaults.overlayCursor,
                overlayCursorSize = sObj.float("overlay_cursor_size") ?: defaults.overlayCursorSize,
            )
          } else {
            defaults
          }
      val bObj = obj.obj("bindings")
      val bindings =
          if (bObj != null) {
            val map = LinkedHashMap<String, WandBinding>()
            for ((k, v) in bObj.fields) {
              val bindingObj = v as? JsonVal.Obj ?: continue
              val actionObj = bindingObj.obj("action") ?: continue
              val action = parseActionObject(actionObj)
              val trigger = WandTriggerMode.fromWire(bindingObj.string("trigger") ?: "once")
              map[k] = WandBinding(action = action, trigger = trigger)
            }
            map
          } else {
            emptyMap()
          }
      WandJsonResult.Ok(
          WandConfig(
              version = version,
              platform = platform,
              settings = settings,
              bindings = bindings,
          ),
      )
    } catch (e: Exception) {
      WandJsonResult.Error(e.message ?: "invalid config JSON")
    }
  }

  fun serializeConfig(config: WandConfig): String {
    val s = config.settings
    val bindingsEntries =
        config.bindings.entries.joinToString(",") { (k, b) ->
          """${quote(k)}:{"action":${serializeAction(b.action)},"trigger":${quote(b.trigger.wire)}}"""
        }
    return buildString {
      append('{')
      append(""""version":${config.version},""")
      append(""""platform":${quote(config.platform)},""")
      append(""""settings":{""")
      append(""""touch_sensitivity":${s.touchSensitivity},""")
      append(""""gyro_x_speed":${s.gyroXSpeed},""")
      append(""""gyro_y_speed":${s.gyroYSpeed},""")
      append(""""gyro_deadzone":${s.gyroDeadzone},""")
      append(""""touch_deadzone":${s.touchDeadzone},""")
      append(""""acceleration_curve":${s.accelerationCurve},""")
      append(""""ema_smoothing":${s.emaSmoothing},""")
      append(""""reverse_scroll":${s.reverseScroll},""")
      append(""""scroll_strength":${s.scrollStrength},""")
      append(""""horizontal_scroll":${s.horizontalScroll},""")
      append(""""tap_in_touch_mode":${s.tapInTouchMode},""")
      append(""""tap_in_gyro_mode":${s.tapInGyroMode},""")
      append(""""auto_reconnect":${s.autoReconnect},""")
      append(""""long_press_ms":${s.longPressMs},""")
      append(""""double_press_ms":${s.doublePressMs},""")
      append(""""radial_dead_radius":${s.radialDeadRadius},""")
      append(""""overlay_cursor":${s.overlayCursor},""")
      append(""""overlay_cursor_size":${s.overlayCursorSize}""")
      append("},")
      append(""""bindings":{$bindingsEntries}""")
      append('}')
    }
  }

  fun parseSample(json: String): WandSample? {
    val trimmed = json.trim()
    if (trimmed.isEmpty() || trimmed == "null") return null
    return try {
      val obj = MiniJsonParser(trimmed).parseValue() as? JsonVal.Obj ?: return null
      if (obj.string("error") != null) return null
      fun parseVec(field: String): Vec3f {
        val v = obj.obj(field) ?: return Vec3f()
        return Vec3f(
            x = v.float("x") ?: 0f,
            y = v.float("y") ?: 0f,
            z = v.float("z") ?: 0f,
        )
      }
      WandSample(
          time = obj.int("time") ?: 0,
          seq = obj.int("seq") ?: 0,
          orientation = parseVec("orientation"),
          accel = parseVec("accel"),
          gyro = parseVec("gyro"),
          touchX = obj.float("touch_x") ?: 0f,
          touchY = obj.float("touch_y") ?: 0f,
          touching = obj.bool("touching") ?: false,
          click = obj.bool("click") ?: false,
          home = obj.bool("home") ?: false,
          app = obj.bool("app") ?: false,
          volDown = obj.bool("vol_down") ?: false,
          volUp = obj.bool("vol_up") ?: false,
      )
    } catch (e: Exception) {
      Log.w("Wand", "Failed to parse sample JSON", e)
      null
    }
  }

  private fun quote(s: String): String = buildString {
    append('"')
    for (ch in s) {
      when (ch) {
        '\\' -> append("\\\\")
        '"' -> append("\\\"")
        '\n' -> append("\\n")
        '\r' -> append("\\r")
        '\t' -> append("\\t")
        else -> append(ch)
      }
    }
    append('"')
  }
}

internal sealed class JsonVal {
  data class Obj(val fields: Map<String, JsonVal>) : JsonVal() {
    fun string(key: String): String? = (fields[key] as? Str)?.value

    fun float(key: String): Float? = (fields[key] as? Num)?.value?.toFloat()

    fun int(key: String): Int? = (fields[key] as? Num)?.value?.toInt()

    fun long(key: String): Long? = (fields[key] as? Num)?.value?.toLong()

    fun bool(key: String): Boolean? = (fields[key] as? Bool)?.value

    fun obj(key: String): Obj? = fields[key] as? Obj
  }

  data class Arr(val items: List<JsonVal>) : JsonVal()

  data class Str(val value: String) : JsonVal()

  data class Num(val value: Double) : JsonVal()

  data class Bool(val value: Boolean) : JsonVal()

  data object Null : JsonVal()
}

internal class MiniJsonParser(private val src: String) {
  private var pos: Int = 0

  fun parseValue(): JsonVal {
    skipWhitespace()
    if (pos >= src.length) throw IllegalArgumentException("unexpected end of JSON")
    return when (val ch = src[pos]) {
      '{' -> parseObject()
      '[' -> parseArray()
      '"' -> JsonVal.Str(parseString())
      't',
      'f' -> parseBoolean()
      'n' -> parseNull()
      '-',
      in '0'..'9' -> parseNumber()
      else -> throw IllegalArgumentException("unexpected token '$ch' at $pos")
    }
  }

  private fun parseObject(): JsonVal.Obj {
    expect('{')
    skipWhitespace()
    val map = LinkedHashMap<String, JsonVal>()
    if (peek() == '}') {
      pos++
      return JsonVal.Obj(map)
    }
    while (true) {
      skipWhitespace()
      val key = parseString()
      skipWhitespace()
      expect(':')
      val value = parseValue()
      map[key] = value
      skipWhitespace()
      when (val ch = peek()) {
        ',' -> pos++
        '}' -> {
          pos++
          return JsonVal.Obj(map)
        }
        else -> throw IllegalArgumentException("expected ',' or '}' at $pos, got '$ch'")
      }
    }
  }

  private fun parseArray(): JsonVal.Arr {
    expect('[')
    skipWhitespace()
    val list = ArrayList<JsonVal>()
    if (peek() == ']') {
      pos++
      return JsonVal.Arr(list)
    }
    while (true) {
      list.add(parseValue())
      skipWhitespace()
      when (val ch = peek()) {
        ',' -> pos++
        ']' -> {
          pos++
          return JsonVal.Arr(list)
        }
        else -> throw IllegalArgumentException("expected ',' or ']' at $pos, got '$ch'")
      }
    }
  }

  private fun parseString(): String {
    expect('"')
    val sb = StringBuilder()
    while (pos < src.length) {
      val ch = src[pos++]
      when (ch) {
        '"' -> return sb.toString()
        '\\' -> {
          if (pos >= src.length) throw IllegalArgumentException("unterminated escape")
          when (val esc = src[pos++]) {
            '"',
            '\\',
            '/' -> sb.append(esc)
            'b' -> sb.append('\b')
            'f' -> sb.append('\u000C')
            'n' -> sb.append('\n')
            'r' -> sb.append('\r')
            't' -> sb.append('\t')
            'u' -> {
              if (pos + 4 > src.length) throw IllegalArgumentException("short unicode escape")
              val hex = src.substring(pos, pos + 4)
              pos += 4
              sb.append(hex.toInt(16).toChar())
            }
            else -> throw IllegalArgumentException("invalid escape '\\$esc'")
          }
        }
        else -> sb.append(ch)
      }
    }
    throw IllegalArgumentException("unterminated string")
  }

  private fun parseBoolean(): JsonVal.Bool =
      when {
        src.startsWith("true", pos) -> {
          pos += 4
          JsonVal.Bool(true)
        }
        src.startsWith("false", pos) -> {
          pos += 5
          JsonVal.Bool(false)
        }
        else -> throw IllegalArgumentException("invalid boolean at $pos")
      }

  private fun parseNull(): JsonVal.Null {
    if (src.startsWith("null", pos)) {
      pos += 4
      return JsonVal.Null
    }
    throw IllegalArgumentException("invalid null at $pos")
  }

  private fun parseNumber(): JsonVal.Num {
    val start = pos
    if (pos < src.length && src[pos] == '-') pos++
    while (pos < src.length && src[pos] in '0'..'9') pos++
    if (pos < src.length && src[pos] == '.') {
      pos++
      while (pos < src.length && src[pos] in '0'..'9') pos++
    }
    if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E')) {
      pos++
      if (pos < src.length && (src[pos] == '+' || src[pos] == '-')) pos++
      while (pos < src.length && src[pos] in '0'..'9') pos++
    }
    val token = src.substring(start, pos)
    val num =
        token.toDoubleOrNull()
            ?: throw IllegalArgumentException("invalid number '$token' at $start")
    return JsonVal.Num(num)
  }

  private fun skipWhitespace() {
    while (pos < src.length && src[pos].isWhitespace()) pos++
  }

  private fun peek(): Char? = if (pos < src.length) src[pos] else null

  private fun expect(expected: Char) {
    if (pos >= src.length || src[pos] != expected) {
      throw IllegalArgumentException("expected '$expected' at $pos")
    }
    pos++
  }
}
