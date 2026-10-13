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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.sin

/** The eight architectural/codex vector plates shared across Web and Android. */
public enum class VitruvianPlateKind(
    public val index: String,
    public val caption: String,
    public val ratio: String,
) {
  Proportion(
      index = "FIG. I",
      caption = "HOMO AD CIRCULUM ET QUADRATUM",
      ratio = "1 : φ (1.618)",
  ),
  Spaces(
      index = "FIG. II",
      caption = "MODULAR GRID · FIBONACCI SPACING",
      ratio = "3 · 5 · 8 · 13 · 21 · 34 · 55",
  ),
  Tabs(
      index = "FIG. III",
      caption = "TABULAR PARTITION · COMPACT TO EXPANDED",
      ratio = "55 DP / 89 DP RAIL",
  ),
  Resources(
      index = "FIG. IV",
      caption = "RESOURCE ALLOCATION · 16-SEGMENT PRESSURE",
      ratio = "16 × 1/16 QUANTUM",
  ),
  Topology(
      index = "FIG. V",
      caption = "CLUSTER TOPOLOGY · CONTROL PLANE QUORUM",
      ratio = "3 CP : N WORKER",
  ),
  Telemetry(
      index = "FIG. VI",
      caption = "HARMONIC TELEMETRY · WAVE & IMPULSE",
      ratio = "ΔT = 220 MS LINEAR",
  ),
  Security(
      index = "FIG. VII",
      caption = "ZERO-TRUST ENVELOPE · ATTESTATION BOUNDARY",
      ratio = "ED25519 / MTLS",
  ),
  Harmonic(
      index = "FIG. VIII",
      caption = "DIATESSARON · DIAPENTE · DIAPASON",
      ratio = "12 : 9 : 8 : 6",
  ),
}

/**
 * Renders one of the eight technical codex plates using Compose [Canvas] hairlines, compass arcs,
 * and registration geometry.
 */
@Composable
public fun VitruvianPlate(
    kind: VitruvianPlateKind,
    modifier: Modifier = Modifier,
    height: Dp = 144.dp,
) {
  val colors = Vitruvian
  val dashEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f))

  Canvas(modifier = modifier.fillMaxWidth().height(height)) {
    val w = size.width
    val h = size.height
    val cx = w / 2f
    val cy = h / 2f
    val r = minOf(w, h) * 0.36f
    val stroke = 1.dp.toPx()
    val accentStroke = 1.5.dp.toPx()

    // Center crosshairs
    drawLine(
        color = colors.line,
        start = Offset(0f, cy),
        end = Offset(w, cy),
        strokeWidth = stroke,
        pathEffect = dashEffect,
    )
    drawLine(
        color = colors.line,
        start = Offset(cx, 0f),
        end = Offset(cx, h),
        strokeWidth = stroke,
        pathEffect = dashEffect,
    )

    when (kind) {
      VitruvianPlateKind.Proportion -> {
        drawRect(
            color = colors.divider,
            topLeft = Offset(cx - r, cy - r),
            size = Size(r * 2f, r * 2f),
            style = Stroke(width = stroke),
        )
        drawCircle(
            color = colors.accent,
            radius = r * 1.12f,
            center = Offset(cx, cy - r * 0.1f),
            style = Stroke(width = accentStroke),
        )
        drawLine(
            color = colors.sanguine,
            start = Offset(cx - r, cy - r),
            end = Offset(cx + r, cy + r),
            strokeWidth = stroke,
            pathEffect = dashEffect,
        )
        drawLine(
            color = colors.sanguine,
            start = Offset(cx + r, cy - r),
            end = Offset(cx - r, cy + r),
            strokeWidth = stroke,
            pathEffect = dashEffect,
        )
        drawCircle(color = colors.accentText, radius = 3.dp.toPx(), center = Offset(cx, cy))
      }
      VitruvianPlateKind.Spaces -> {
        val fib = listOf(3f, 5f, 8f, 13f, 21f, 34f, 55f)
        val total = fib.sum()
        var cursorX = w * 0.1f
        val barW = w * 0.8f
        val barH = h * 0.52f
        val topY = (h - barH) / 2f
        fib.forEachIndexed { idx, step ->
          val segW = barW * (step / total)
          drawRect(
              color = if (idx >= 4) colors.accentQuiet else colors.surface2,
              topLeft = Offset(cursorX, topY),
              size = Size(segW, barH),
          )
          drawRect(
              color = if (idx == 5) colors.accent else colors.divider,
              topLeft = Offset(cursorX, topY),
              size = Size(segW, barH),
              style = Stroke(width = stroke),
          )
          cursorX += segW
        }
      }
      VitruvianPlateKind.Tabs -> {
        val frameW = w * 0.76f
        val frameH = h * 0.68f
        val left = (w - frameW) / 2f
        val top = (h - frameH) / 2f
        val railW = frameW * 0.22f
        drawRect(
            color = colors.divider,
            topLeft = Offset(left, top),
            size = Size(frameW, frameH),
            style = Stroke(width = stroke),
        )
        drawRect(
            color = colors.accentQuiet,
            topLeft = Offset(left, top),
            size = Size(railW, frameH),
        )
        drawLine(
            color = colors.accent,
            start = Offset(left, top),
            end = Offset(left, top + frameH * 0.35f),
            strokeWidth = accentStroke * 1.5f,
        )
        drawLine(
            color = colors.divider,
            start = Offset(left + railW, top),
            end = Offset(left + railW, top + frameH),
            strokeWidth = stroke,
        )
      }
      VitruvianPlateKind.Resources -> {
        val count = 16
        val barW = w * 0.8f
        val gap = 3.dp.toPx()
        val cellW = (barW - gap * (count - 1)) / count
        val cellH = h * 0.36f
        val startX = (w - barW) / 2f
        val topY = (h - cellH) / 2f
        for (i in 0 until count) {
          val x = startX + i * (cellW + gap)
          val fill =
              when {
                i < 10 -> colors.accent
                i < 13 -> colors.warn
                else -> colors.surface2
              }
          drawRect(
              color = fill,
              topLeft = Offset(x, topY),
              size = Size(cellW, cellH),
          )
        }
      }
      VitruvianPlateKind.Topology -> {
        val nodes =
            listOf(
                Offset(cx, cy - r * 0.85f),
                Offset(cx - r * 0.9f, cy + r * 0.65f),
                Offset(cx + r * 0.9f, cy + r * 0.65f),
            )
        drawCircle(
            color = colors.divider,
            radius = r,
            center = Offset(cx, cy),
            style = Stroke(width = stroke, pathEffect = dashEffect),
        )
        for (i in nodes.indices) {
          val a = nodes[i]
          val b = nodes[(i + 1) % nodes.size]
          drawLine(color = colors.accent, start = a, end = b, strokeWidth = stroke)
          drawLine(color = colors.line, start = a, end = Offset(cx, cy), strokeWidth = stroke)
          drawCircle(color = colors.surface, radius = 6.dp.toPx(), center = a)
          drawCircle(
              color = colors.accentText,
              radius = 6.dp.toPx(),
              center = a,
              style = Stroke(width = accentStroke),
          )
        }
        drawCircle(color = colors.sanguine, radius = 4.dp.toPx(), center = Offset(cx, cy))
      }
      VitruvianPlateKind.Telemetry -> {
        val steps = 48
        val startX = w * 0.08f
        val spanW = w * 0.84f
        val amp = h * 0.28f
        var prev = Offset(startX, cy)
        for (i in 1..steps) {
          val t = i.toFloat() / steps
          val x = startX + spanW * t
          val y = cy - sin(t * PI * 3.0).toFloat() * amp
          val next = Offset(x, y)
          drawLine(color = colors.accent, start = prev, end = next, strokeWidth = accentStroke)
          prev = next
        }
      }
      VitruvianPlateKind.Security -> {
        for (scale in listOf(1.0f, 0.72f, 0.44f)) {
          val side = r * 2f * scale
          drawRect(
              color = if (scale == 0.72f) colors.accent else colors.divider,
              topLeft = Offset(cx - side / 2f, cy - side / 2f),
              size = Size(side, side),
              style = Stroke(width = if (scale == 0.72f) accentStroke else stroke),
          )
        }
        drawCircle(color = colors.ok, radius = 4.dp.toPx(), center = Offset(cx, cy))
      }
      VitruvianPlateKind.Harmonic -> {
        val ratios = listOf(1.0f, 0.75f, 0.666f, 0.5f)
        ratios.forEachIndexed { idx, factor ->
          drawCircle(
              color = if (idx == 0 || idx == 2) colors.accent else colors.divider,
              radius = r * 1.15f * factor,
              center = Offset(cx, cy),
              style = Stroke(width = if (idx == 0) accentStroke else stroke),
          )
        }
      }
    }
  }
}

/**
 * A framed [Plate] containing a [VitruvianPlate] vector illustration and its architectural
 * caption/ratio footer.
 */
@Composable
public fun PlateFigure(
    kind: VitruvianPlateKind,
    modifier: Modifier = Modifier,
    marks: Boolean = true,
    height: Dp = 144.dp,
) {
  val colors = Vitruvian
  Plate(
      modifier = modifier.fillMaxWidth(),
      marks = marks,
      gridField = true,
  ) {
    Column(modifier = Modifier.fillMaxWidth()) {
      Row(
          modifier =
              Modifier.fillMaxWidth()
                  .bottomHairline(colors.line)
                  .padding(horizontal = Space.s3, vertical = Space.s2),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Label(text = kind.index, color = colors.accentText)
        VText(text = kind.ratio, style = VitruvianType.listSub, color = colors.textDim)
      }
      VitruvianPlate(kind = kind, height = height)
      Row(
          modifier = Modifier.fillMaxWidth().padding(horizontal = Space.s3, vertical = Space.s2),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Label(text = kind.caption)
      }
    }
  }
}
