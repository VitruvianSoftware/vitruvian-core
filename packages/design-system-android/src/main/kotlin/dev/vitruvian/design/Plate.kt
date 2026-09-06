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

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

private val HAIRLINE = 1.dp

/** Registration-mark geometry, straight from `.plate > .corner` in the CSS. */
private val MARK_SIZE = 11.dp
private val MARK_ARM = 5.dp
private val MARK_OUTSET = 6.dp

/** Grid pitch of `.grid-field`. */
private val GRID_PITCH = 21.dp

private val DASH_ON = 4.dp
private val DASH_OFF = 4.dp

/**
 * Everything framed is a Plate: a 1 dp divider border plus four registration marks drawn outside
 * its corners.
 *
 * @param marks whether to draw the four registration crosses. The CSS puts them on explicitly per
 *   instance (`<i class="corner tl">`), so this mirrors that rather than drawing them
 *   unconditionally.
 * @param dashed a dashed border, as the edit-mode "add widget" plate and the sideload plate use.
 * @param gridField the 21 dp blueprint grid the trackpad and panel preview sit on.
 */
@Composable
public fun Plate(
    modifier: Modifier = Modifier,
    marks: Boolean = false,
    dashed: Boolean = false,
    gridField: Boolean = false,
    borderColor: Color = Vitruvian.divider,
    content: @Composable BoxScope.() -> Unit,
) {
  val gridColor = Vitruvian.line
  val markColor = Vitruvian.accentText
  Box(
      modifier =
          modifier.drawBehind {
            if (gridField) drawGridField(gridColor)
            drawPlateBorder(borderColor, dashed)
            if (marks) drawRegistrationMarks(markColor)
          },
      content = content,
  )
}

/** The 1 dp frame. Corners are square - the radius tokens are all zero. */
private fun DrawScope.drawPlateBorder(color: Color, dashed: Boolean) {
  val width = HAIRLINE.toPx()
  val effect =
      if (dashed) {
        PathEffect.dashPathEffect(floatArrayOf(DASH_ON.toPx(), DASH_OFF.toPx()))
      } else {
        null
      }
  drawRect(
      color = color,
      topLeft = Offset(width / 2f, width / 2f),
      size = Size(size.width - width, size.height - width),
      style = Stroke(width = width, pathEffect = effect),
  )
}

/**
 * The four 11 dp crosses, each offset 6 dp outside its corner.
 *
 * The CSS builds each one from two absolutely-positioned pseudo-elements: a 1 px vertical bar 5 px
 * in from the mark's left edge, and a 1 px horizontal bar 5 px down from its top. That is exactly
 * what is drawn here.
 */
private fun DrawScope.drawRegistrationMarks(color: Color) {
  val markSize = MARK_SIZE.toPx()
  val arm = MARK_ARM.toPx()
  val outset = MARK_OUTSET.toPx()
  val hairline = HAIRLINE.toPx()
  val origins =
      listOf(
          Offset(-outset, -outset),
          Offset(size.width - markSize + outset, -outset),
          Offset(-outset, size.height - markSize + outset),
          Offset(size.width - markSize + outset, size.height - markSize + outset),
      )
  origins.forEach { origin ->
    drawRect(
        color = color,
        topLeft = Offset(origin.x + arm, origin.y),
        size = Size(hairline, markSize),
    )
    drawRect(
        color = color,
        topLeft = Offset(origin.x, origin.y + arm),
        size = Size(markSize, hairline),
    )
  }
}

/** `repeating-linear-gradient` at a 21 dp pitch, in both axes. */
private fun DrawScope.drawGridField(color: Color) {
  val pitch = GRID_PITCH.toPx()
  val hairline = HAIRLINE.toPx()
  if (pitch <= 0f) return
  var x = 0f
  while (x < size.width) {
    drawRect(color = color, topLeft = Offset(x, 0f), size = Size(hairline, size.height))
    x += pitch
  }
  var y = 0f
  while (y < size.height) {
    drawRect(color = color, topLeft = Offset(0f, y), size = Size(size.width, hairline))
    y += pitch
  }
}

/** A 1 dp hairline rule in `color.divider`. */
@Composable
public fun Rule(modifier: Modifier = Modifier, color: Color = Vitruvian.divider) {
  Box(modifier = modifier.drawBehind { drawRect(color) })
}

/** The VMark: a 1 dp square with an inscribed circle. */
@Composable
public fun VMark(
    modifier: Modifier = Modifier,
    markSize: Dp = 17.dp,
    color: Color = Vitruvian.accentText,
) {
  Box(
      modifier =
          modifier.size(markSize).drawBehind {
            val hairline = HAIRLINE.toPx()
            drawRect(color = color, style = Stroke(width = hairline))
            drawOval(
                color = color,
                topLeft = Offset(hairline / 2f, hairline / 2f),
                size = Size(size.width - hairline, size.height - hairline),
                style = Stroke(width = hairline),
            )
          },
  )
}

/**
 * The hairline that separates list rows, log rows and table rows.
 *
 * Drawn rather than composed so a row's own height stays exactly the language's 55 dp, with no
 * extra divider box in the layout.
 */
public fun Modifier.bottomHairline(color: Color): Modifier = drawBehind {
  val width = HAIRLINE.toPx()
  drawRect(
      color = color,
      topLeft = Offset(0f, size.height - width),
      size = Size(size.width, width),
  )
}
