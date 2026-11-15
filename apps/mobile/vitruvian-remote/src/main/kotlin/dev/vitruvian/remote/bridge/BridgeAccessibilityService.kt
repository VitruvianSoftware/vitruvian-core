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

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import dev.vitruvian.remote.state.BridgePolicy
import dev.vitruvian.remote.state.ScreenKey
import dev.vitruvian.remote.state.ScreenNode
import dev.vitruvian.remote.state.ScreenPolicy
import dev.vitruvian.remote.state.ToolTier
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

/**
 * The phone's screen, as tools: read it, tap it, type into it, press its keys.
 *
 * An `AccessibilityService` is the only API on Android that can do any of this without a rooted
 * phone or a per-session MediaProjection dialog, and it is bound by the SYSTEM after the user turns
 * it on in Settings -- so, like the notification listener, it lives outside the bridge's own
 * service and hands itself to the tools through [instance].
 *
 * The act tools stay behind the trust window; that gate is in `PhoneBridgeService.handleCall` and
 * is not repeated here, because a second copy of a security rule is a second thing to get wrong.
 * What IS repeated in every tool is the service check, because "the service is off" is the failure
 * a person can actually fix and it must never come back as a null pointer.
 */
public class BridgeAccessibilityService : AccessibilityService() {

  override fun onServiceConnected() {
    super.onServiceConnected()
    instance = this
  }

  /**
   * Nothing.
   *
   * The service declares the two window event types because a service that subscribes to no events
   * is not offered `rootInActiveWindow` on every Android version -- the events are the price of the
   * window content, not something this app wants to react to.
   */
  override fun onAccessibilityEvent(event: AccessibilityEvent?): Unit = Unit

  override fun onInterrupt(): Unit = Unit

  override fun onDestroy() {
    if (instance === this) instance = null
    super.onDestroy()
  }

  override fun onUnbind(intent: android.content.Intent?): Boolean {
    if (instance === this) instance = null
    return super.onUnbind(intent)
  }

  public companion object {
    @Volatile internal var instance: BridgeAccessibilityService? = null

    /**
     * Whether the user has turned the service on.
     *
     * Asked of `AccessibilityManager` rather than of [instance], for the same reason the
     * notification listener asks the system: between the switch and the bind there is a window in
     * which the honest answer is "on, connecting" rather than "not granted".
     */
    public fun enabled(context: Context): Boolean =
        runCatching {
              val wanted = ComponentName(context, BridgeAccessibilityService::class.java)
              context
                  .getSystemService(AccessibilityManager::class.java)
                  ?.getEnabledAccessibilityServiceList(
                      android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                  ?.any {
                    it.resolveInfo?.serviceInfo?.let { info ->
                      info.packageName == wanted.packageName && info.name == wanted.className
                    } == true
                  } == true
            }
            .getOrDefault(false)
  }
}

/** `screen.tree`, `screen.screenshot` and the five act tools. */
public object ScreenTools {

  public fun all(context: Context): List<PhoneTool> =
      listOf(
          tree(context),
          screenshot(context),
          tap(context),
          longPress(context),
          swipe(context),
          type(context),
          key(context),
      )

  // --- screen.tree ------------------------------------------------------

  private fun tree(context: Context): PhoneTool =
      tool(
          name = "screen.tree",
          tier = ToolTier.Read,
          description =
              "What is on the phone's screen: every node with text, a label, or something you " +
                  "can do to it -- its role, text, view id, bounds and flags. Bounds are " +
                  "\"left,top,right,bottom\" in screen pixels, the same coordinates screen.tap " +
                  "and screen.swipe take, so the centre of a node's bounds is where to tap it.",
          inputSchema =
              """
              {"type":"object","properties":{
                "format":{"type":"string","enum":["text","json"],"description":"text (default, indented by depth) or json"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        requireService(context)
            ?: run {
              val service = BridgeAccessibilityService.instance!!
              val roots = roots(service)
              if (roots.isEmpty()) {
                ToolResult(
                    "nothing to read: no window is showing its content. The screen may be off " +
                        "or locked -- try screen.key with \"home\" first.",
                    true,
                )
              } else {
                val nodes = ArrayList<ScreenNode>()
                var truncated = false
                roots.forEach { root -> if (!truncated) truncated = walk(root, 0, nodes) }
                val root = roots.first()
                val pkg = root.packageName?.toString().orEmpty()
                val window = root.text?.toString().orEmpty()
                if (args.optString("format").trim().lowercase() == "json") {
                  ToolResult(json(pkg, window, nodes, truncated))
                } else {
                  ToolResult(ScreenPolicy.formatTree(pkg, window, nodes, truncated))
                }
              }
            }
      }

  /**
   * The windows worth reading: the active one, then any other interactive window.
   *
   * The second half is what makes a dialog, a keyboard suggestion strip or a picture-in-picture
   * player visible at all -- `rootInActiveWindow` is one window, and on a foldable there are
   * routinely two apps on screen.
   */
  private fun roots(service: BridgeAccessibilityService): List<AccessibilityNodeInfo> {
    val found = LinkedHashMap<Int, AccessibilityNodeInfo>()
    runCatching { service.rootInActiveWindow }.getOrNull()?.let { found[it.windowId] = it }
    runCatching { service.windows }
        .getOrNull()
        ?.forEach { window ->
          runCatching { window.root }
              .getOrNull()
              ?.let { root -> found.putIfAbsent(root.windowId, root) }
        }
    return found.values.toList()
  }

  /**
   * Depth-first, keeping only nodes an agent could act on or read.
   *
   * Returns whether the cap was hit. A layout tree is mostly nameless `FrameLayout`s wrapping each
   * other, and printing them would bury the six lines that matter under two hundred that do not --
   * but the DEPTH of a kept node is its real depth, so the indentation still shows what contains
   * what.
   */
  private fun walk(
      node: AccessibilityNodeInfo?,
      depth: Int,
      into: MutableList<ScreenNode>
  ): Boolean {
    node ?: return false
    if (into.size >= ScreenPolicy.MAX_NODES) return true
    val text = node.text?.toString().orEmpty()
    val desc = node.contentDescription?.toString().orEmpty()
    val interesting =
        text.isNotBlank() ||
            desc.isNotBlank() ||
            node.isClickable ||
            node.isEditable ||
            node.isFocused ||
            node.isScrollable
    if (interesting) {
      val rect = Rect()
      runCatching { node.getBoundsInScreen(rect) }
      into.add(
          ScreenNode(
              depth = depth,
              role = ScreenPolicy.shortRole(node.className?.toString()),
              text = text,
              desc = desc,
              viewId = ScreenPolicy.shortViewId(node.viewIdResourceName),
              bounds = ScreenPolicy.bounds(rect.left, rect.top, rect.right, rect.bottom),
              flags = flags(node),
          ))
    }
    var truncated = false
    for (i in 0 until node.childCount) {
      if (truncated) break
      truncated = walk(runCatching { node.getChild(i) }.getOrNull(), depth + 1, into)
    }
    return truncated || into.size >= ScreenPolicy.MAX_NODES
  }

  // isChecked is deprecated for a three-state getChecked() that only exists on
  // API 36; this app's floor is 26, so the boolean is the one that works
  // everywhere and the tri-state would have to be version-gated to say the
  // same thing.
  @Suppress("DEPRECATION")
  private fun flags(node: AccessibilityNodeInfo): List<String> = buildList {
    if (node.isClickable) add("clickable")
    if (node.isLongClickable) add("long-clickable")
    if (node.isEditable) add("editable")
    if (node.isFocused) add("focused")
    if (node.isScrollable) add("scrollable")
    if (node.isCheckable) add(if (node.isChecked) "checked" else "unchecked")
    if (!node.isEnabled) add("disabled")
  }

  private fun json(
      packageName: String,
      window: String,
      nodes: List<ScreenNode>,
      truncated: Boolean,
  ): String {
    val array = JSONArray()
    nodes.forEach { node ->
      array.put(
          JSONObject()
              .put("depth", node.depth)
              .put("role", node.role)
              .put("text", node.text)
              .put("desc", node.desc)
              .put("view_id", node.viewId)
              .put("bounds", node.bounds)
              .put("flags", JSONArray(node.flags)))
    }
    return JSONObject()
        .put("package", packageName)
        .put("window", window)
        .put("nodes", array)
        .put("count", nodes.size)
        .put("truncated", truncated)
        .toString()
  }

  // --- screen.screenshot ------------------------------------------------

  private fun screenshot(context: Context): PhoneTool =
      tool(
          name = "screen.screenshot",
          tier = ToolTier.Read,
          description =
              "A picture of the phone's screen, as a JPEG, downscaled to the width you ask for. " +
                  "The text item beside it gives the pixel size; screen.tap takes coordinates in " +
                  "the phone's own screen pixels, not in this picture's.",
          inputSchema =
              """
              {"type":"object","properties":{
                "width":{"type":"integer","description":"Pixels wide, default 800, clamped to 200-1600"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        requireService(context)
            ?: if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
              ToolResult(
                  "screen.screenshot needs Android 11 or newer; this phone is on Android " +
                      "${Build.VERSION.RELEASE}. Use screen.tree, which works on every version.",
                  true,
              )
            } else {
              capture(
                  BridgeAccessibilityService.instance!!,
                  ScreenPolicy.clampWidth(args.optInt("width")))
            }
      }

  /**
   * One frame, downscaled, as JPEG.
   *
   * Blocking on a latch because the whole tool is blocking -- the bridge runs it on an IO thread
   * and the Mac agent is holding the call open. The hardware buffer is closed in a `finally`: it is
   * a graphics allocation, and leaking one per screenshot is how an app that works fine in a demo
   * runs the phone out of memory in an afternoon.
   */
  private fun capture(service: BridgeAccessibilityService, width: Int): ToolResult {
    val latch = CountDownLatch(1)
    var bitmap: Bitmap? = null
    var failure: String? = null
    runCatching {
          service.takeScreenshot(
              Display.DEFAULT_DISPLAY,
              { runnable -> runnable.run() },
              object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                  val buffer = result.hardwareBuffer
                  try {
                    bitmap =
                        Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                            ?.copy(Bitmap.Config.ARGB_8888, false)
                  } finally {
                    buffer.close()
                    latch.countDown()
                  }
                }

                override fun onFailure(errorCode: Int) {
                  failure = "the system refused the screenshot (code $errorCode)"
                  latch.countDown()
                }
              },
          )
        }
        .onFailure {
          return ToolResult("could not take a screenshot: ${it.message}", true)
        }
    if (!latch.await(CAPTURE_TIMEOUT_S, TimeUnit.SECONDS)) {
      return ToolResult("the screenshot did not arrive within $CAPTURE_TIMEOUT_S s", true)
    }
    failure?.let {
      return ToolResult(
          "$it. Android refuses screenshots of secure windows -- a banking app, a password " +
              "field or the lock screen.",
          true,
      )
    }
    val full = bitmap ?: return ToolResult("the screenshot came back empty", true)
    val scaled = downscale(full, width)
    val bytes = ByteArrayOutputStream()
    scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, bytes)
    val base64 =
        android.util.Base64.encodeToString(bytes.toByteArray(), android.util.Base64.NO_WRAP)
    if (scaled !== full) scaled.recycle()
    val text =
        JSONObject()
            .put("width", scaled.width)
            .put("height", scaled.height)
            .put("screen_width", full.width)
            .put("screen_height", full.height)
            .put("mime_type", BridgePolicy.JPEG)
            .toString()
    full.recycle()
    return ToolResult(text, isError = false, imageBase64 = base64)
  }

  /** Never upscales: a 400-pixel-wide copy of a 1080-pixel screen blown back up is just blur. */
  private fun downscale(source: Bitmap, width: Int): Bitmap {
    if (source.width <= width) return source
    val height = (source.height.toLong() * width / source.width).toInt().coerceAtLeast(1)
    return Bitmap.createScaledBitmap(source, width, height, true)
  }

  // --- the act tools ----------------------------------------------------

  private fun tap(context: Context): PhoneTool =
      tool(
          name = "screen.tap",
          tier = ToolTier.Act,
          description =
              "Taps the screen at a point, in screen pixels -- the centre of a node's bounds " +
                  "from screen.tree.",
          inputSchema = POINT_SCHEMA,
      ) { args ->
        requireService(context)
            ?: point(args)?.let { (x, y) -> gesture(stroke(x, y, x, y, TAP_MS), "tapped at $x,$y") }
            ?: ToolResult(NEEDS_POINT, true)
      }

  private fun longPress(context: Context): PhoneTool =
      tool(
          name = "screen.long_press",
          tier = ToolTier.Act,
          description = "Presses and holds at a point for 700 ms -- what opens a context menu.",
          inputSchema = POINT_SCHEMA,
      ) { args ->
        requireService(context)
            ?: point(args)?.let { (x, y) ->
              gesture(stroke(x, y, x, y, LONG_PRESS_MS), "long-pressed at $x,$y")
            }
            ?: ToolResult(NEEDS_POINT, true)
      }

  private fun swipe(context: Context): PhoneTool =
      tool(
          name = "screen.swipe",
          tier = ToolTier.Act,
          description =
              "Drags from one point to another -- a scroll, a swipe away, a slider. Screen pixels.",
          inputSchema =
              """
              {"type":"object","required":["x1","y1","x2","y2"],"properties":{
                "x1":{"type":"integer"},"y1":{"type":"integer"},
                "x2":{"type":"integer"},"y2":{"type":"integer"},
                "ms":{"type":"integer","description":"How long the drag takes, default 300"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        requireService(context)
            ?: run {
              val x1 = args.optInt("x1", -1)
              val y1 = args.optInt("y1", -1)
              val x2 = args.optInt("x2", -1)
              val y2 = args.optInt("y2", -1)
              if (x1 < 0 || y1 < 0 || x2 < 0 || y2 < 0) {
                ToolResult(
                    "\"x1\", \"y1\", \"x2\" and \"y2\" are all required, in screen pixels", true)
              } else {
                val ms =
                    args.optInt("ms", SWIPE_MS).coerceIn(MIN_GESTURE_MS, MAX_GESTURE_MS).toLong()
                gesture(stroke(x1, y1, x2, y2, ms), "swiped $x1,$y1 → $x2,$y2 in $ms ms")
              }
            }
      }

  private fun type(context: Context): PhoneTool =
      tool(
          name = "screen.type",
          tier = ToolTier.Act,
          description =
              "Types into whatever text field has focus on the phone. Tap the field first with " +
                  "screen.tap; with append:true the text is added to what is already there.",
          inputSchema =
              """
              {"type":"object","required":["text"],"properties":{
                "text":{"type":"string"},
                "append":{"type":"boolean","description":"Add to the field's current text instead of replacing it"}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val text = args.optString("text")
        when {
          text.isEmpty() -> ToolResult("\"text\" is required", true)
          else -> requireService(context) ?: setText(text, args.optBoolean("append", false))
        }
      }

  private fun setText(text: String, append: Boolean): ToolResult {
    val service =
        BridgeAccessibilityService.instance ?: return ToolResult(ScreenPolicy.NEEDS_SERVICE, true)
    val root = runCatching { service.rootInActiveWindow }.getOrNull()
    val focused =
        runCatching { root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) }.getOrNull()
            ?: return ToolResult(NO_FIELD, true)
    if (!focused.isEditable) return ToolResult(NO_FIELD, true)
    val existing = if (append) focused.text?.toString().orEmpty() else ""
    val whole = existing + text
    val arguments =
        Bundle().apply {
          putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, whole)
        }
    if (!focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) {
      return ToolResult(
          "the focused field refused the text. Some apps only accept typing through the " +
              "keyboard; tap the field and try screen.key instead.",
          true,
      )
    }
    // The caret goes to the end, so a second append continues rather than
    // overwriting -- and so the app's own send button acts on a field whose
    // selection is where a person's would be.
    runCatching {
      focused.performAction(
          AccessibilityNodeInfo.ACTION_SET_SELECTION,
          Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, whole.length)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, whole.length)
          },
      )
    }
    return ToolResult(JSONObject().put("typed", text.length).put("appended", append).toString())
  }

  private fun key(context: Context): PhoneTool =
      tool(
          name = "screen.key",
          tier = ToolTier.Act,
          description = "Presses one of the phone's system keys: ${ScreenPolicy.keyNames()}.",
          inputSchema =
              """
              {"type":"object","required":["key"],"properties":{
                "key":{"type":"string","enum":["back","home","recents","notifications","quick_settings","lock"]}
              }}
              """
                  .trimIndent(),
      ) { args ->
        val wanted = ScreenPolicy.key(args.optString("key"))
        when {
          wanted == null -> ToolResult("\"key\" must be one of: ${ScreenPolicy.keyNames()}", true)
          else -> requireService(context) ?: press(wanted)
        }
      }

  private fun press(key: ScreenKey): ToolResult {
    val service =
        BridgeAccessibilityService.instance ?: return ToolResult(ScreenPolicy.NEEDS_SERVICE, true)
    if (key == ScreenKey.Lock && Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
      return ToolResult(
          "locking the screen needs Android 9 or newer; this phone is on Android " +
              "${Build.VERSION.RELEASE}.",
          true,
      )
    }
    val action =
        when (key) {
          ScreenKey.Back -> AccessibilityService.GLOBAL_ACTION_BACK
          ScreenKey.Home -> AccessibilityService.GLOBAL_ACTION_HOME
          ScreenKey.Recents -> AccessibilityService.GLOBAL_ACTION_RECENTS
          ScreenKey.Notifications -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
          ScreenKey.QuickSettings -> AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS
          ScreenKey.Lock -> AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN
        }
    val ok = runCatching { service.performGlobalAction(action) }.getOrDefault(false)
    return if (ok) {
      ToolResult(JSONObject().put("pressed", key.wire).toString())
    } else {
      ToolResult("the phone refused the ${key.wire} key", true)
    }
  }

  // --- gesture plumbing -------------------------------------------------

  private fun stroke(x1: Int, y1: Int, x2: Int, y2: Int, ms: Long): GestureDescription {
    val path = Path()
    path.moveTo(x1.toFloat(), y1.toFloat())
    // A tap is a path of one point, which GestureDescription rejects; the
    // lineTo to the same point makes it a zero-length stroke, which it takes.
    path.lineTo(x2.toFloat(), y2.toFloat())
    return GestureDescription.Builder()
        .addStroke(GestureDescription.StrokeDescription(path, 0L, ms.coerceAtLeast(1L)))
        .build()
  }

  /**
   * Dispatches a gesture and waits for the system to say it landed.
   *
   * Waiting matters: `dispatchGesture` returns true the moment the gesture is QUEUED, and an agent
   * told "tapped" that then reads the screen half a frame later sees the screen it tapped on.
   */
  private fun gesture(description: GestureDescription, done: String): ToolResult {
    val service =
        BridgeAccessibilityService.instance ?: return ToolResult(ScreenPolicy.NEEDS_SERVICE, true)
    val latch = CountDownLatch(1)
    var cancelled = false
    val callback =
        object : AccessibilityService.GestureResultCallback() {
          override fun onCompleted(gestureDescription: GestureDescription?) = latch.countDown()

          override fun onCancelled(gestureDescription: GestureDescription?) {
            cancelled = true
            latch.countDown()
          }
        }
    val queued =
        runCatching { service.dispatchGesture(description, callback, null) }.getOrDefault(false)
    if (!queued) {
      return ToolResult(
          "the phone would not take the gesture. Another accessibility service may be " +
              "holding the screen, or the display is off.",
          true,
      )
    }
    if (!latch.await(GESTURE_TIMEOUT_S, TimeUnit.SECONDS)) {
      return ToolResult("the gesture did not finish within $GESTURE_TIMEOUT_S s", true)
    }
    return if (cancelled) {
      ToolResult(
          "the gesture was cancelled, usually because a touch came from the screen itself", true)
    } else {
      ToolResult(JSONObject().put("did", done).toString())
    }
  }

  private fun point(args: JSONObject): Pair<Int, Int>? {
    val x = args.optInt("x", -1)
    val y = args.optInt("y", -1)
    return if (x < 0 || y < 0) null else x to y
  }

  /** The refusal when the service is off, or null when it is on and bound. */
  private fun requireService(context: Context): ToolResult? {
    if (!BridgeAccessibilityService.enabled(context)) {
      val row = BridgePermissions.byId(BridgePermissions.ACCESSIBILITY)
      return ToolResult(
          row?.let { BridgePermissions.missing(it) } ?: ScreenPolicy.NEEDS_SERVICE, true)
    }
    if (BridgeAccessibilityService.instance == null) {
      return ToolResult(
          "the accessibility service is on but Android has not connected it yet. Give it a few " +
              "seconds; if it does not, turn Vitruvian Remote off and on under Settings → " +
              "Accessibility.",
          true,
      )
    }
    return null
  }

  private const val NEEDS_POINT = "\"x\" and \"y\" are both required, in screen pixels"

  private const val NO_FIELD =
      "no focused text field. Tap the field first with screen.tap -- screen.tree marks the " +
          "editable nodes and gives their bounds."

  private val POINT_SCHEMA =
      """
      {"type":"object","required":["x","y"],"properties":{
        "x":{"type":"integer","description":"Screen pixels from the left"},
        "y":{"type":"integer","description":"Screen pixels from the top"}
      }}
      """
          .trimIndent()

  private const val TAP_MS = 60L
  private const val LONG_PRESS_MS = 700L
  private const val SWIPE_MS = 300
  private const val MIN_GESTURE_MS = 20
  private const val MAX_GESTURE_MS = 10_000
  private const val GESTURE_TIMEOUT_S = 15L
  private const val CAPTURE_TIMEOUT_S = 15L
  private const val JPEG_QUALITY = 80
}
