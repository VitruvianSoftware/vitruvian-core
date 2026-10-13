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
 * The Lucide outline glyphs the shell and apps use, as raw path data on a 24-unit viewport.
 *
 * Keeping them as path strings rather than as `ImageVector`s means the geometry is byte-identical
 * to the icons the Web design system draws, and adding one is a single line.
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
  public const val SEARCH: String = "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4.35-4.35"
  public const val COPY: String = "M9 9h11v11H9zM5 15H4V4h11v1"
  public const val CHECK: String = "M20 6L9 17l-5-5"
  public const val CHEVRON_RIGHT: String = "M9 18l6-6-6-6"
  public const val CHEVRON_DOWN: String = "M6 9l6 6 6-6"
  public const val CLOSE: String = "M18 6L6 18M6 6l12 12"
  public const val PLUS: String = "M12 5v14M5 12h14"
  public const val TRASH: String = "M3 6h18M8 6V4h8v2M6 6v14h12V6M10 11v6M14 11v6"
  public const val EXTERNAL_LINK: String = "M15 3h6v6M10 14L21 3M18 13v6H5V6h6"
  public const val KEY: String = "M7.5 15.5a4.5 4.5 0 1 1 3.18-7.68L21 8v4h-3v3h-3v3l-4.32-2.5z"
  public const val SHIELD: String = "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"
  public const val CPU: String =
      "M6 6h12v12H6zM9 9h6v6H9zM9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"
  public const val DATABASE: String =
      "M4 6c0-1.66 3.58-3 8-3s8 1.34 8 3-3.58 3-8 3-8-1.34-8-3zM4 6v12c0 1.66 3.58 3 8 3s8-1.34 8-3V6M4 12c0 1.66 3.58 3 8 3s8-1.34 8-3"
  public const val GIT_BRANCH: String =
      "M6 3v12M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM18 9a9 9 0 0 1-9 9"
  public const val SPEAKER: String = "M4 2h16v20H4zM12 6h.01M12 10a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"
  public const val GLOBE: String =
      "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"
  public const val SPARKLES: String =
      "M12 3l1.9 5.8L20 10.7l-5.8 1.9L12 18.4l-2.2-5.8L4 10.7l6.1-1.9zM5 3v4M3 5h4M19 17v4M17 19h4"
  public const val LAYERS: String = "M12 2L2 7l10 5 10-5-10-5zM2 12l10 5 10-5M2 17l10 5 10-5"
  public const val LOCK: String = "M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4"
  public const val REFRESH: String =
      "M21 2v6h-6M3 12a9 9 0 0 1 15-6.7L21 8M3 22v-6h6M21 12a9 9 0 0 1-15 6.7L3 16"
  public const val ALERT_TRIANGLE: String = "M12 3L2 20h20L12 3zM12 9v5M12 17h.01"

  /** All 28 canonical icon paths in the Vitruvian icon set. */
  public val ALL: Map<String, String> =
      mapOf(
          "HOME" to HOME,
          "MOUSE_POINTER" to MOUSE_POINTER,
          "ACTIVITY" to ACTIVITY,
          "GRID_2X2" to GRID_2X2,
          "TERMINAL" to TERMINAL,
          "SETTINGS" to SETTINGS,
          "PANEL_RIGHT" to PANEL_RIGHT,
          "SEARCH" to SEARCH,
          "COPY" to COPY,
          "CHECK" to CHECK,
          "CHEVRON_RIGHT" to CHEVRON_RIGHT,
          "CHEVRON_DOWN" to CHEVRON_DOWN,
          "CLOSE" to CLOSE,
          "PLUS" to PLUS,
          "TRASH" to TRASH,
          "EXTERNAL_LINK" to EXTERNAL_LINK,
          "KEY" to KEY,
          "SHIELD" to SHIELD,
          "CPU" to CPU,
          "DATABASE" to DATABASE,
          "GIT_BRANCH" to GIT_BRANCH,
          "SPEAKER" to SPEAKER,
          "GLOBE" to GLOBE,
          "SPARKLES" to SPARKLES,
          "LAYERS" to LAYERS,
          "LOCK" to LOCK,
          "REFRESH" to REFRESH,
          "ALERT_TRIANGLE" to ALERT_TRIANGLE,
      )
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
