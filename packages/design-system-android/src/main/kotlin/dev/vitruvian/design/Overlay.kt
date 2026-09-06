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
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/** The scrim over which every overlay sits: 55% of `color.bg`. */
private const val SCRIM_ALPHA = 0.55f

private val DIALOG_MAX_WIDTH = 400.dp
private val SHEET_MAX_WIDTH = 560.dp

/**
 * `.dialog` - glass over a 55% ink scrim, with registration marks.
 *
 * Destructive variants differ only in their kicker colour and their action button; the typed
 * confirmation is the caller's business, since whether it is required is a host setting.
 */
@Composable
public fun VDialog(
    onDismissRequest: () -> Unit,
    kicker: String,
    kickerColor: Color,
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  Dialog(
      onDismissRequest = onDismissRequest,
      properties = DialogProperties(usePlatformDefaultWidth = false),
  ) {
    Box(
        modifier = Modifier.fillMaxSize().background(colors.bg.copy(alpha = SCRIM_ALPHA)),
        contentAlignment = Alignment.Center,
    ) {
      Plate(
          modifier =
              modifier
                  .padding(Space.s5)
                  .widthIn(max = DIALOG_MAX_WIDTH)
                  .shadow(Shadow.lg)
                  .glassGround(),
          marks = true,
      ) {
        Column(
            modifier = Modifier.padding(Space.s5),
            verticalArrangement = Arrangement.spacedBy(Space.s4),
        ) {
          Label(text = kicker, color = kickerColor)
          VText(text = title, style = VitruvianType.h2, color = colors.text)
          VText(
              text = body,
              style = VitruvianType.body.copy(fontSize = FontSize.h5),
              color = colors.textDim,
          )
          content()
        }
      }
    }
  }
}

/**
 * The bottom glass sheet the macro editor uses.
 *
 * Tapping the scrim dismisses; tapping the sheet does not, which is why the sheet swallows its own
 * clicks with no indication.
 */
@Composable
public fun BottomSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  val swallow = remember { MutableInteractionSource() }
  Dialog(
      onDismissRequest = onDismissRequest,
      properties = DialogProperties(usePlatformDefaultWidth = false),
  ) {
    Box(
        modifier =
            Modifier.fillMaxSize()
                .background(colors.bg.copy(alpha = SCRIM_ALPHA))
                .clickable(
                    interactionSource = swallow,
                    indication = null,
                    onClick = onDismissRequest,
                ),
        contentAlignment = Alignment.BottomCenter,
    ) {
      Column(
          modifier =
              modifier
                  .fillMaxWidth()
                  .widthIn(max = SHEET_MAX_WIDTH)
                  .shadow(Shadow.lg)
                  .glassGround()
                  .border(1.dp, colors.divider)
                  .clickable(interactionSource = swallow, indication = null) {}
                  .padding(horizontal = Space.s4, vertical = Space.s5),
          verticalArrangement = Arrangement.spacedBy(Space.s4),
          content = content,
      )
    }
  }
}

/**
 * The glass ground: a blurred backdrop under a 66%-alpha surface where the platform supports it,
 * and an opaque surface where it does not.
 */
@Composable
public fun Modifier.glassGround(): Modifier {
  val colors = Vitruvian
  return if (supportsGlass) {
    this.glassBlur().background(colors.glass)
  } else {
    this.background(colors.surface)
  }
}

/** A floating menu: glass, 200 dp minimum, hairline-separated mono items. */
@Composable
public fun MenuSurface(
    modifier: Modifier = Modifier,
    minWidth: Dp = 200.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  Column(
      modifier =
          modifier
              .widthIn(min = minWidth)
              .shadow(Shadow.md)
              .glassGround()
              .border(1.dp, colors.divider),
      content = content,
  )
}
