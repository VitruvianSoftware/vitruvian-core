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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/** The banner's three severities. */
public enum class BannerTone {
  Info,
  Warn,
  Err
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
