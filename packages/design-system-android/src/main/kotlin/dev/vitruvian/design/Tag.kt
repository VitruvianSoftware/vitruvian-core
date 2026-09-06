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

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The tag palette. Each maps to one `.tag-*` rule. */
public enum class TagTone {
  Accent,
  Ok,
  Warn,
  Sanguine,
  Neutral,
  Outline
}

/** `color-mix(in srgb, <c> 16%, transparent)` - the tag's ground. */
private const val TAG_FILL_ALPHA = 0.16f

/** `color-mix(in srgb, <c> 40%, transparent)` - the tag's border. */
private const val TAG_BORDER_ALPHA = 0.40f

/**
 * `.tag` - a mono, tracked, uppercase chip.
 *
 * Made clickable only when [onClick] is supplied, which is how the Apps screen's module chips work;
 * everywhere else a Tag is a static status marker.
 */
@Composable
public fun Tag(
    text: String,
    modifier: Modifier = Modifier,
    tone: TagTone = TagTone.Outline,
    onClick: (() -> Unit)? = null,
    minHeight: Dp = Dp.Unspecified,
    contentPadding: PaddingValues = PaddingValues(horizontal = Space.s3, vertical = 3.dp),
) {
  val colors = Vitruvian
  val (fill, content, border) =
      when (tone) {
        TagTone.Accent ->
            Triple(
                colors.accentQuiet, colors.accentText, colors.accent.copy(alpha = TAG_BORDER_ALPHA))
        TagTone.Ok ->
            Triple(
                colors.ok.copy(alpha = TAG_FILL_ALPHA),
                colors.ok,
                colors.ok.copy(alpha = TAG_BORDER_ALPHA),
            )
        TagTone.Warn ->
            Triple(
                colors.warn.copy(alpha = TAG_FILL_ALPHA),
                colors.warn,
                colors.warn.copy(alpha = TAG_BORDER_ALPHA),
            )
        TagTone.Sanguine ->
            Triple(
                colors.sanguine.copy(alpha = TAG_FILL_ALPHA),
                colors.sanguineText,
                colors.sanguine.copy(alpha = TAG_BORDER_ALPHA),
            )
        TagTone.Neutral -> Triple(colors.surface2, colors.textDim, colors.divider)
        TagTone.Outline -> Triple(Color.Transparent, colors.textDim, colors.divider)
      }
  Box(
      modifier =
          modifier
              .then(
                  if (minHeight != Dp.Unspecified) {
                    Modifier.defaultMinSize(minHeight = minHeight)
                  } else {
                    Modifier
                  })
              .background(fill)
              .border(1.dp, border)
              .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
              .padding(contentPadding),
      contentAlignment = Alignment.Center,
  ) {
    VText(
        text = text.uppercase(),
        style = VitruvianType.tag,
        color = content,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        softWrap = false,
    )
  }
}

/**
 * `.kbd` - a mono chip with a doubled bottom border, used for modifier keys and for the console's
 * recent-command chips.
 */
@Composable
public fun Kbd(
    text: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
  val colors = Vitruvian
  Box(
      modifier =
          modifier
              .then(if (onClick != null) Modifier.defaultMinSize(minHeight = 32.dp) else Modifier)
              .border(1.dp, colors.divider)
              .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
              .padding(horizontal = 6.dp, vertical = 2.dp),
      contentAlignment = Alignment.Center,
  ) {
    VText(
        text = text,
        style = VitruvianType.listSub,
        color = colors.textDim,
        maxLines = 1,
        softWrap = false,
    )
  }
}
