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

/**
 * What the screen tools say, kept away from Android so it can be tested on the JVM.
 *
 * Same reason as `BridgePolicy.kt`, and the same failure shape: everything here is wrong QUIETLY. A
 * tree formatter that drops the view id, or indents every node at zero, still returns a tree the
 * agent happily reads and then taps the wrong thing with. A width that is not clamped asks the
 * phone for a 12000-pixel JPEG and the tool times out with no error to point at. A key name that
 * silently maps to nothing turns "go back" into a no-op the agent reports as done.
 *
 * The Android half -- `BridgeAccessibilityService.kt` -- walks the real node tree and calls in here
 * to turn it into text. No `org.json`: it is a platform class, not a JVM one, and one import of it
 * would make every test in this file an instrumentation test.
 */

/**
 * A key the screen tools can press.
 *
 * An enum rather than the raw `AccessibilityService.GLOBAL_ACTION_*` ints so the name-to-action
 * parsing is testable here; the service maps each case to its constant, which is then the only line
 * of it that has to be right on a device.
 */
public enum class ScreenKey(public val wire: String) {
  Back("back"),
  Home("home"),
  Recents("recents"),
  Notifications("notifications"),
  QuickSettings("quick_settings"),

  /** Needs API 28; the tool says so rather than doing nothing. */
  Lock("lock"),
}

/**
 * One node of the screen, already reduced to what an agent can act on.
 *
 * [depth] is the indent in the text form; [bounds] is "l,t,r,b" in SCREEN pixels -- the same space
 * `screen.tap` and `screen.swipe` take, which is what makes "tap the node you just read" work.
 */
public data class ScreenNode(
    val depth: Int,
    val role: String,
    val text: String = "",
    val desc: String = "",
    val viewId: String = "",
    val bounds: String = "",
    val flags: List<String> = emptyList(),
)

/** The rules the screen tools share. */
public object ScreenPolicy {
  /**
   * The node cap.
   *
   * A settings screen is a few dozen nodes; a chat app mid-scroll is thousands, and the whole tree
   * of one would be a bigger prompt than the conversation the agent is having about it.
   */
  public const val MAX_NODES: Int = 400

  /** `screen.screenshot`'s default width, in pixels. */
  public const val DEFAULT_WIDTH: Int = 800

  public const val MIN_WIDTH: Int = 200

  public const val MAX_WIDTH: Int = 1600

  /** What every screen tool answers when the accessibility service is off. */
  public const val NEEDS_SERVICE: String =
      "the screen tools need the accessibility service, which is off. On the phone: " +
          "Settings → Accessibility → Vitruvian Remote → turn on."

  /**
   * A width the phone can actually render.
   *
   * Clamped rather than refused: an agent asking for 4000 means "as big as you can", and an error
   * there costs a round trip to learn a number it could simply have been given.
   */
  public fun clampWidth(requested: Int): Int =
      if (requested <= 0) DEFAULT_WIDTH else requested.coerceIn(MIN_WIDTH, MAX_WIDTH)

  /**
   * The key an agent named, or null -- the tool then lists the six rather than pressing nothing.
   */
  public fun key(name: String): ScreenKey? {
    val wanted = name.trim().lowercase().replace('-', '_').replace(' ', '_')
    return ScreenKey.entries.firstOrNull { it.wire == wanted }
  }

  /** The six key names, for the error text and the schema. */
  public fun keyNames(): String = ScreenKey.entries.joinToString(", ") { it.wire }

  /** Bounds as the tree prints them, and as [parseBounds] reads them back. */
  public fun bounds(left: Int, top: Int, right: Int, bottom: Int): String =
      "$left,$top,$right,$bottom"

  /**
   * The four numbers of an "l,t,r,b", or null.
   *
   * Here so an agent can hand a bounds string straight back instead of doing the midpoint
   * arithmetic itself -- and so that a malformed one is a sentence rather than a tap at (0, 0),
   * which on most phones is the status bar.
   */
  public fun parseBounds(text: String): IntArray? {
    val parts = text.split(',').map { it.trim() }
    if (parts.size != BOUNDS_PARTS) return null
    val numbers = parts.map { it.toIntOrNull() ?: return null }
    return numbers.toIntArray()
  }

  /** The centre of an "l,t,r,b", which is what tapping a node means. */
  public fun centre(text: String): IntArray? {
    val b = parseBounds(text) ?: return null
    return intArrayOf((b[0] + b[BOUNDS_RIGHT]) / 2, (b[1] + b[BOUNDS_BOTTOM]) / 2)
  }

  /** `android.widget.TextView` → `TextView`. The package tells an agent nothing. */
  public fun shortRole(className: String?): String {
    val name = className.orEmpty().trim()
    if (name.isEmpty()) return "node"
    return name.substringAfterLast('.').ifEmpty { name }
  }

  /** `dev.vitruvian.remote:id/send` → `send`. Same reason. */
  public fun shortViewId(resourceName: String?): String {
    val name = resourceName.orEmpty().trim()
    if (name.isEmpty()) return ""
    return name.substringAfterLast('/').ifEmpty { name }
  }

  /**
   * The tree as text: one line per node, indented by depth.
   *
   * Text rather than JSON by default because this is read by a model that is about to decide where
   * to tap, and two hundred nodes of `{"role":…,"text":…}` spends its attention on punctuation.
   * `format:"json"` is there for anything that parses instead of reads.
   */
  public fun formatTree(
      packageName: String,
      window: String,
      nodes: List<ScreenNode>,
      truncated: Boolean = false,
  ): String = buildString {
    append("package=").append(packageName.ifBlank { "unknown" })
    if (window.isNotBlank()) append(" window=\"").append(oneLine(window)).append('"')
    append(" nodes=").append(nodes.size)
    for (node in nodes) {
      append('\n')
      repeat(node.depth.coerceAtLeast(0)) { append("  ") }
      append(node.role.ifBlank { "node" })
      if (node.text.isNotBlank()) append(" \"").append(oneLine(node.text)).append('"')
      if (node.desc.isNotBlank()) append(" (").append(oneLine(node.desc)).append(')')
      if (node.viewId.isNotBlank()) append(" #").append(node.viewId)
      if (node.bounds.isNotBlank()) append(" [").append(node.bounds).append(']')
      node.flags.filter { it.isNotBlank() }.forEach { append(' ').append(it) }
    }
    if (truncated) {
      append("\n… stopped at ").append(MAX_NODES)
      append(" nodes; the rest of the screen is not shown. Scroll, or open a smaller screen.")
    }
  }

  /**
   * A node's text, on one line and clipped.
   *
   * A newline inside a label would put the child of one node at the indentation of another, and
   * whoever reads the tree has no way to tell that apart from the real structure.
   */
  private fun oneLine(value: String): String =
      value.replace('\n', ' ').replace('\r', ' ').trim().let {
        if (it.length <= VALUE_MAX) it else it.take(VALUE_MAX) + "…"
      }

  private const val BOUNDS_PARTS = 4
  private const val BOUNDS_RIGHT = 2
  private const val BOUNDS_BOTTOM = 3
  private const val VALUE_MAX = 120
}
