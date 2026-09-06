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

import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** The four button roles the language has. */
public enum class ButtonVariant {
  Primary,
  Secondary,
  Ghost,
  Danger
}

private val DISABLED_ALPHA = 0.4f

/**
 * `.btn` and its variants.
 *
 * Height floors at [Hit.h1] because every clickable in this language does; the press state is the
 * flat `accentQuiet` fill supplied by [FlatIndication], never a ripple.
 */
@Composable
public fun VButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: ButtonVariant = ButtonVariant.Secondary,
    enabled: Boolean = true,
    dashed: Boolean = false,
    borderColor: Color? = null,
    contentColor: Color? = null,
    contentPadding: PaddingValues = PaddingValues(horizontal = Space.s5),
) {
  val colors = Vitruvian
  val border =
      borderColor
          ?: when (variant) {
            ButtonVariant.Primary -> colors.accent
            ButtonVariant.Danger -> colors.sanguine
            ButtonVariant.Ghost -> Color.Transparent
            ButtonVariant.Secondary -> colors.divider
          }
  val fill = if (variant == ButtonVariant.Primary) colors.accent else Color.Transparent
  val text =
      contentColor
          ?: when (variant) {
            ButtonVariant.Primary -> colors.onAccent
            ButtonVariant.Danger -> colors.sanguineText
            else -> colors.text
          }
  val interactionSource = remember { MutableInteractionSource() }
  Box(
      modifier =
          modifier
              .defaultMinSize(minHeight = Hit.h1)
              .alpha(if (enabled) 1f else DISABLED_ALPHA)
              .background(fill)
              .clickable(
                  enabled = enabled,
                  interactionSource = interactionSource,
                  indication = LocalIndication.current,
                  onClick = onClick,
              )
              .drawBehind {
                val width = 1.dp.toPx()
                drawRect(
                    color = border,
                    style =
                        Stroke(
                            width = width,
                            pathEffect =
                                if (dashed) {
                                  PathEffect.dashPathEffect(
                                      floatArrayOf(4.dp.toPx(), 4.dp.toPx()),
                                  )
                                } else {
                                  null
                                },
                        ),
                )
              }
              .padding(contentPadding),
      contentAlignment = Alignment.Center,
  ) {
    VText(
        text = label.uppercase(),
        style = VitruvianType.buttonTouch.copy(textAlign = TextAlign.Center),
        color = text,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        softWrap = false,
    )
  }
}
