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
   * Spoken description for a [Status] indicator so TalkBack never relies on colour alone. An
   * explicit [label] overrides the default state word derived from [tone]; when [text] is present,
   * the state word and caption are combined into a single spoken description.
   */
  /** Default accessible trackpad announcement describing pointer and click gestures. */
  public const val TRACKPAD_DESCRIPTION: String =
      "Trackpad. Drag to move the pointer, tap to click."

  /** Default spoken word for [tone], or [label] when an explicit state label is provided. */
  public fun toneStateWord(tone: StatusTone, label: String? = null): String =
      label?.takeIf { it.isNotBlank() }
          ?: when (tone) {
            StatusTone.Ok -> "OK"
            StatusTone.Warn -> "Warning"
            StatusTone.Crit -> "Error"
            StatusTone.Neutral -> "Idle"
            StatusTone.Run -> "Running"
          }

  /**
   * Formats an accessible status label without repeating [toneStateWord] when the visible [text]
   * caption already communicates that state word.
   */
  public fun statusLabel(
      tone: StatusTone,
      text: String? = null,
      label: String? = null,
  ): String {
    val stateWord = toneStateWord(tone = tone, label = label)
    val caption = text?.trim()?.takeIf { it.isNotEmpty() } ?: return stateWord
    val containsStateWord =
        Regex("(?i)\\b${Regex.escape(stateWord.trim())}\\b").containsMatchIn(caption)
    return if (containsStateWord) caption else "$stateWord, $caption"
  }

  /** Accessible label for [HostChip]: `"<name>, <state>. Opens settings."` */
  public fun hostChipDescription(name: String, state: String): String {
    val cleanName = name.trim().ifEmpty { "Mac" }
    val cleanState = state.trim().ifEmpty { "Unknown" }
    return "$cleanName, $cleanState. Opens settings."
  }

  /** Alpha-composites an ARGB foreground color over an opaque ARGB background color. */
  public fun compositeOver(fgArgb: Int, bgArgb: Int): Int {
    val alpha = ((fgArgb ushr 24) and 0xFF) / 255.0
    if (alpha >= 1.0) return fgArgb
    val fgR = (fgArgb ushr 16) and 0xFF
    val fgG = (fgArgb ushr 8) and 0xFF
    val fgB = fgArgb and 0xFF
    val bgR = (bgArgb ushr 16) and 0xFF
    val bgG = (bgArgb ushr 8) and 0xFF
    val bgB = bgArgb and 0xFF
    val r = (fgR * alpha + bgR * (1.0 - alpha) + 0.5).toInt().coerceIn(0, 255)
    val g = (fgG * alpha + bgG * (1.0 - alpha) + 0.5).toInt().coerceIn(0, 255)
    val b = (fgB * alpha + bgB * (1.0 - alpha) + 0.5).toInt().coerceIn(0, 255)
    return (0xFF shl 24) or (r shl 16) or (g shl 8) or b
  }

  /** WCAG 2.1 relative luminance for an ARGB color in sRGB space. */
  public fun relativeLuminance(argb: Int): Double {
    fun linearize(channel: Int): Double {
      val srgb = (channel and 0xFF) / 255.0
      return if (srgb <= 0.04045) srgb / 12.92 else Math.pow((srgb + 0.055) / 1.055, 2.4)
    }
    val r = linearize(argb ushr 16)
    val g = linearize(argb ushr 8)
    val b = linearize(argb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  /** WCAG 2.1 contrast ratio between [fgArgb] (composited over [bgArgb]) and [bgArgb]. */
  public fun contrastRatio(fgArgb: Int, bgArgb: Int): Double {
    val fg = compositeOver(fgArgb = fgArgb, bgArgb = bgArgb)
    val l1 = relativeLuminance(fg)
    val l2 = relativeLuminance(bgArgb)
    val lighter = maxOf(l1, l2)
    val darker = minOf(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
  }

  /**
   * Semantics contract for a [Tag]: only clickable tags are interactive (expanding their touch
   * target floor to [Hit.h1] without changing their visual height and exposing [Role.Button] plus
   * optional [selected] state). A non-clickable tag is static even if [selected] is passed.
   */
  public data class TagSemantics(
      val interactive: Boolean,
      val hasButtonRole: Boolean,
      val selected: Boolean?,
  )

  public fun tagSemantics(
      clickable: Boolean,
      selected: Boolean? = null,
  ): TagSemantics =
      if (clickable) {
        TagSemantics(
            interactive = true,
            hasButtonRole = true,
            selected = selected,
        )
      } else {
        TagSemantics(
            interactive = false,
            hasButtonRole = false,
            selected = null,
        )
      }

  /**
   * Spoken description for a navigation item's icon: null when the text label is rendered beside
   * the icon, and [label] when the item is icon-only.
   */
  public fun navIconDescription(label: String, iconOnly: Boolean): String? =
      if (iconOnly) label.takeIf { it.isNotBlank() } else null

  /**
   * Spoken description for a [VButton]: an explicit [contentDescription] wins; unambiguous media
   * transport glyphs fall back to their spoken names; ordinary text labels return null so the
   * button's text is read directly.
   */
  public fun buttonContentDescription(label: String, contentDescription: String? = null): String? =
      contentDescription?.takeIf { it.isNotBlank() }
          ?: when (label.trim()) {
            "⏮" -> "Previous track"
            "▶" -> "Play"
            "⏸" -> "Pause"
            "⏭" -> "Next track"
            else -> null
          }
}
