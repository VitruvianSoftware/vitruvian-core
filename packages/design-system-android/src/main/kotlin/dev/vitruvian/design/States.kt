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

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The banner's three severities. */
public enum class BannerTone {
  Info,
  Warn,
  Err,
}

/** `color-mix(in srgb, <c> 8%, transparent)` - the banner's ground. */
private const val BANNER_FILL_ALPHA = 0.08f

/**
 * `.banner` - a bordered strip with a doubled rule on its leading edge.
 *
 * The offline banner is the only one this app shows, but the tone is kept open because the language
 * defines all three.
 */
@Composable
public fun Banner(
    tone: BannerTone,
    label: String,
    body: String,
    modifier: Modifier = Modifier,
    actions: @Composable (RowScope.() -> Unit)? = null,
) {
  val colors = Vitruvian
  val rule =
      when (tone) {
        BannerTone.Info -> colors.accent
        BannerTone.Warn -> colors.warn
        BannerTone.Err -> colors.sanguine
      }
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .background(rule.copy(alpha = BANNER_FILL_ALPHA))
              .drawBehind {
                val hairline = 1.dp.toPx()
                drawRect(
                    color = colors.divider,
                    style = Stroke(width = hairline),
                )
                drawRect(
                    color = rule,
                    size = Size(2.dp.toPx(), size.height),
                )
              }
              .padding(Space.s4),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.s1)) {
      Label(text = label, color = rule)
      VText(
          text = body,
          style = VitruvianType.body.copy(fontSize = FontSize.mono),
          color = colors.textDim,
      )
    }
    actions?.invoke(this)
  }
}

/**
 * `.plate` with a dashed border - the empty state.
 *
 * Used for "no Mac paired", which also locks navigation to Hosts.
 */
@Composable
public fun EmptyState(
    label: String,
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    actions: @Composable (RowScope.() -> Unit)? = null,
) {
  val colors = Vitruvian
  Plate(modifier = modifier.fillMaxWidth(), dashed = true) {
    Column(
        modifier = Modifier.padding(horizontal = Space.s5, vertical = Space.s6),
        verticalArrangement = Arrangement.spacedBy(Space.s4),
    ) {
      VMark(markSize = 28.dp)
      Label(label)
      VText(text = title, style = VitruvianType.h2, color = colors.text)
      VText(
          text = body,
          style = VitruvianType.body.copy(fontSize = FontSize.h5),
          color = colors.textDim,
      )
      if (actions != null) {
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3), content = actions)
      }
    }
  }
}

/**
 * `.skeleton` - a square loading placeholder that pulses linearly between 0.35 and 0.90 alpha
 * (collapsing to static 0.65 under reduced motion).
 */
@Composable
public fun Skeleton(
    modifier: Modifier = Modifier,
    height: Dp = 18.dp,
) {
  val colors = Vitruvian
  val alpha =
      if (LocalReduceMotion.current) {
        0.65f
      } else {
        val transition = rememberInfiniteTransition(label = "skeleton")
        val value by
            transition.animateFloat(
                initialValue = 0.35f,
                targetValue = 0.90f,
                animationSpec =
                    infiniteRepeatable(
                        animation = tween(durationMillis = 1200, easing = LinearEasing),
                        repeatMode = RepeatMode.Reverse,
                    ),
                label = "skeletonAlpha",
            )
        value
      }
  Box(
      modifier =
          modifier
              .fillMaxWidth()
              .height(height)
              .alpha(alpha)
              .background(colors.surface2)
              .border(1.dp, colors.line),
  )
}

/**
 * `.spinner` - a technical compass-arc activity indicator that rotates linearly (or renders a
 * static three-quarter arc under reduced motion).
 */
@Composable
public fun Spinner(
    modifier: Modifier = Modifier,
    spinnerSize: Dp = 18.dp,
    color: Color = Vitruvian.accentText,
    trackColor: Color = Vitruvian.line,
) {
  val angle =
      if (LocalReduceMotion.current) {
        0f
      } else {
        val transition = rememberInfiniteTransition(label = "spinner")
        val value by
            transition.animateFloat(
                initialValue = 0f,
                targetValue = 360f,
                animationSpec =
                    infiniteRepeatable(
                        animation = tween(durationMillis = 900, easing = LinearEasing),
                        repeatMode = RepeatMode.Restart,
                    ),
                label = "spinnerAngle",
            )
        value
      }
  Canvas(modifier = modifier.size(spinnerSize)) {
    val stroke = 1.5.dp.toPx()
    val inset = stroke / 2f
    val arcSize = Size(size.width - stroke, size.height - stroke)
    drawOval(
        color = trackColor,
        topLeft = Offset(inset, inset),
        size = arcSize,
        style = Stroke(width = stroke),
    )
    rotate(degrees = angle) {
      drawArc(
          color = color,
          startAngle = -90f,
          sweepAngle = 110f,
          useCenter = false,
          topLeft = Offset(inset, inset),
          size = arcSize,
          style = Stroke(width = stroke, cap = StrokeCap.Square),
      )
    }
  }
}
