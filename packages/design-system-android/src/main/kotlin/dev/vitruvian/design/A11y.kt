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
  public fun statusLabel(
      tone: StatusTone,
      text: String? = null,
      label: String? = null,
  ): String {
    val stateWord =
        label?.takeIf { it.isNotBlank() }
            ?: when (tone) {
              StatusTone.Ok -> "OK"
              StatusTone.Warn -> "Warning"
              StatusTone.Crit -> "Error"
              StatusTone.Neutral -> "Idle"
              StatusTone.Run -> "Running"
            }
    val caption = text?.trim()?.takeIf { it.isNotEmpty() }
    return if (caption != null) "$stateWord, $caption" else stateWord
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
