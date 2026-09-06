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

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The Lucide outline glyphs the shell uses, as raw path data on a 24-unit viewport.
 *
 * Keeping them as path strings rather than as `ImageVector`s means the geometry is byte-identical
 * to the icons the design prototype draws, and adding one is a single line.
 */
public object VitruvianIcons {
  public const val HOME: String = "M3 11l9-8 9 8v10a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1z"
  public const val MOUSE_POINTER: String = "M4 4l7 17 2-7 7-2z"
  public const val ACTIVITY: String = "M3 12h4l3-8 4 16 3-8h4"
  public const val GRID_2X2: String = "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z"
  public const val TERMINAL: String = "M4 17l6-6-6-6M12 19h8"
  public const val SETTINGS: String =
      "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 2v3M12 19v3M2 12h3M19 12h3"
  public const val PANEL_RIGHT: String = "M3 4h18v16H3zM15 4v16"
}

/** The viewport every glyph above is drawn on. */
private const val VIEWPORT = 24f

/** Lucide's stroke width, in viewport units. */
private const val STROKE = 1.5f

/** A 20 dp, 1.5-stroke outline glyph. */
@Composable
public fun VIcon(
    path: String,
    modifier: Modifier = Modifier,
    iconSize: Dp = 20.dp,
    color: Color = LocalContentColor.current,
) {
  val parsed = remember(path) { PathParser().parsePathString(path).toPath() }
  Canvas(modifier = modifier.size(iconSize)) {
    val scale = size.minDimension / VIEWPORT
    withTransform({ scale(scale, scale, pivot = Offset.Zero) }) {
      drawPath(
          path = parsed,
          color = color,
          style = Stroke(width = STROKE, cap = StrokeCap.Round, join = StrokeJoin.Round),
      )
    }
  }
}
