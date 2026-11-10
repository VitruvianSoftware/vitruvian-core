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

package dev.vitruvian.design

/** The status square's five states. */
public enum class StatusTone {
  Neutral,
  Ok,
  Warn,
  Crit,
  Run,
}

/**
 * Pure accessibility rules for the design system, kept free of Compose so plain JVM tests can pin
 * them alongside [OptionList] and [SafeArea].
 */
public object A11y {
  /** Minimum interactive touch target floor in dp ([Hit.h1]). */
  public const val MIN_TOUCH_TARGET_DP: Int = 44

  /** Default visual height of a compact tag/chip in dp. */
  public const val TAG_VISUAL_HEIGHT_DP: Int = 32

  /**
   * How [VIcon] exposes itself to TalkBack: decorative when [contentDescription] is null or blank
   * (its semantics are cleared so a sibling label is not read twice), and an `Image` with that
   * description when non-blank.
   */
  public data class IconSemantics(
      val isDecorative: Boolean,
      val contentDescription: String?,
  )

  public fun iconSemantics(contentDescription: String?): IconSemantics =
      if (contentDescription.isNullOrBlank()) {
        IconSemantics(isDecorative = true, contentDescription = null)
      } else {
        IconSemantics(isDecorative = false, contentDescription = contentDescription)
      }

  /**
   * Spoken state word for a [Status] indicator so TalkBack never relies on colour alone. An
   * explicit [label] overrides the default derived from [tone].
   */
  public fun statusLabel(tone: StatusTone, label: String? = null): String {
    if (!label.isNullOrBlank()) return label
    return when (tone) {
      StatusTone.Ok -> "OK"
      StatusTone.Warn -> "Warning"
      StatusTone.Crit -> "Error"
      StatusTone.Neutral -> "Idle"
      StatusTone.Run -> "Running"
    }
  }

  /**
   * Touch-target and semantics contract for a [Tag]: static tags keep their visual height, while
   * clickable or selectable tags expand their touch target floor to [MIN_TOUCH_TARGET_DP] (44 dp,
   * [Hit.h1]) without changing their visual height.
   */
  public data class TagSemantics(
      val interactive: Boolean,
      val minTouchHeightDp: Int,
      val visualHeightDp: Int,
      val hasButtonRole: Boolean,
      val selected: Boolean?,
  )

  public fun tagSemantics(
      clickable: Boolean,
      selected: Boolean? = null,
      visualHeightDp: Int = TAG_VISUAL_HEIGHT_DP,
  ): TagSemantics {
    val interactive = clickable || selected != null
    return TagSemantics(
        interactive = interactive,
        minTouchHeightDp =
            if (interactive) maxOf(visualHeightDp, MIN_TOUCH_TARGET_DP) else visualHeightDp,
        visualHeightDp = visualHeightDp,
        hasButtonRole = interactive,
        selected = selected,
    )
  }

  /**
   * Spoken description for a navigation item's icon: null when the text label is rendered beside
   * the icon, and [label] when the item is icon-only.
   */
  public fun navIconDescription(label: String, iconOnly: Boolean): String? =
      if (iconOnly) label.takeIf { it.isNotBlank() } else null

  /**
   * Spoken description for a [VButton]: an explicit [contentDescription] wins; known single-glyph
   * labels fall back to their spoken names; ordinary text labels return null so the button's text
   * is read directly.
   */
  public fun buttonContentDescription(label: String, contentDescription: String? = null): String? =
      contentDescription?.takeIf { it.isNotBlank() }
          ?: when (label.trim()) {
            "⏮" -> "Previous track"
            "▶" -> "Play"
            "⏸" -> "Pause"
            "⏭" -> "Next track"
            "−",
            "-" -> "Volume down"
            "+" -> "Volume up"
            "×" -> "Remove widget"
            else -> null
          }
}
