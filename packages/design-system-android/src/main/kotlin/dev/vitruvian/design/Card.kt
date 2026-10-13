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
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

/** Surface treatments for a [Card] plate. */
public enum class CardSurface {
  Plate,
  Fill,
  Glass,
}

/**
 * `.card` - a framed plate with optional kicker, title, metadata caption, and live indicator.
 *
 * Mirrors the Web `<Card>` component and the specification in `ANDROID.md`.
 */
@Composable
public fun Card(
    modifier: Modifier = Modifier,
    kicker: String? = null,
    title: String? = null,
    meta: String? = null,
    surface: CardSurface = CardSurface.Plate,
    marks: Boolean = false,
    dashed: Boolean = false,
    live: Boolean = false,
    contentPadding: PaddingValues = PaddingValues(Space.s4),
    headerTrailing: @Composable (RowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
  val colors = Vitruvian
  val background =
      when (surface) {
        CardSurface.Plate -> Color.Transparent
        CardSurface.Fill -> colors.surface
        CardSurface.Glass -> colors.glass
      }
  Plate(
      modifier = modifier.fillMaxWidth().background(background),
      marks = marks,
      dashed = dashed,
      borderColor = colors.divider,
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(contentPadding),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      if (kicker != null || live) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s2),
        ) {
          if (live) {
            Status(tone = StatusTone.Run)
          }
          if (kicker != null) {
            Label(text = kicker)
          }
        }
      }
      if (title != null || meta != null || headerTrailing != null) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          if (title != null) {
            VText(
                text = title,
                modifier = Modifier.weight(1f),
                style = VitruvianType.barTitle,
                color = colors.text,
            )
          }
          if (meta != null) {
            VText(
                text = meta,
                style = VitruvianType.listSub,
                color = colors.textDim,
            )
          }
          headerTrailing?.invoke(this)
        }
      }
      content()
    }
  }
}
