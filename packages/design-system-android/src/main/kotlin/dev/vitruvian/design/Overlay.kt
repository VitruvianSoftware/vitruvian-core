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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
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
    // The real frosted-glass effect: the app behind this window is blurred, the dialog's own
    // text stays sharp.
    blurBehindWindow()
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
    blurBehindWindow()
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
 * The glass ground: a 66%-alpha surface where the platform supports glass, an opaque surface where
 * it does not.
 *
 * The blur that belongs with this is a blur of the scene BEHIND the surface, not of the surface
 * itself, so it cannot live in this modifier chain -- a dialog gets it from [blurBehindWindow] at
 * the window level. Blurring here would frost the dialog's own title and body text. See Glass.kt.
 */
@Composable
public fun Modifier.glassGround(): Modifier {
  val colors = Vitruvian
  return this.background(if (supportsGlass) colors.glass else colors.surface)
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

/** `.menu-item` - a 36 dp clickable row inside a [MenuSurface] or [BottomSheet]. */
@Composable
public fun MenuItem(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    meta: String? = null,
    danger: Boolean = false,
) {
  val colors = Vitruvian
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .defaultMinSize(minHeight = 36.dp)
              .clickable(onClick = onClick)
              .padding(horizontal = Space.s3, vertical = Space.s2),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.SpaceBetween,
  ) {
    VText(
        text = label,
        style = VitruvianType.log,
        color = if (danger) colors.sanguineText else colors.text,
        maxLines = 1,
    )
    if (meta != null) {
      VText(
          text = meta,
          style = VitruvianType.listSub,
          color = colors.textDim,
          maxLines = 1,
      )
    }
  }
}

/** `.menu-divider` - a 1 dp hairline rule between menu groups. */
@Composable
public fun MenuDivider(modifier: Modifier = Modifier) {
  Box(modifier = modifier.fillMaxWidth().height(1.dp).background(Vitruvian.divider))
}

/** `.toast` - a transient status notification plate with a 2 dp leading status rule. */
@Composable
public fun Toast(
    title: String,
    modifier: Modifier = Modifier,
    tone: StatusTone = StatusTone.Ok,
    detail: String? = null,
    onDismiss: (() -> Unit)? = null,
) {
  val colors = Vitruvian
  val rule =
      when (tone) {
        StatusTone.Ok -> colors.ok
        StatusTone.Warn -> colors.warn
        StatusTone.Crit -> colors.sanguine
        StatusTone.Run -> colors.accent
        StatusTone.Neutral -> colors.divider
      }
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .shadow(Shadow.md)
              .glassGround()
              .drawBehind {
                drawRect(color = colors.divider, style = Stroke(width = 1.dp.toPx()))
                drawRect(color = rule, size = Size(2.dp.toPx(), size.height))
              }
              .padding(horizontal = Space.s4, vertical = Space.s3),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Status(tone = tone)
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      VText(text = title, style = VitruvianType.mono, color = colors.text)
      if (detail != null) {
        VText(text = detail, style = VitruvianType.listSub, color = colors.textDim)
      }
    }
    if (onDismiss != null) {
      VButton(
          label = "×",
          onClick = onDismiss,
          variant = ButtonVariant.Ghost,
      )
    }
  }
}
