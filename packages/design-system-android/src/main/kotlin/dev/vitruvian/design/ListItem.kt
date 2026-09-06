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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * `.list-item` - the 55 dp row this language uses instead of a card per item.
 *
 * @param selectedRule the 2 dp accent rule on the left edge that marks the selected host;
 *   [Color.Transparent] elsewhere.
 */
@Composable
public fun ListItem(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    status: StatusTone? = null,
    onClick: (() -> Unit)? = null,
    selectedRule: Color = Color.Transparent,
    titleColor: Color = LocalContentColor.current,
    contentPadding: PaddingValues = PaddingValues(horizontal = Space.s4, vertical = Space.s3),
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .defaultMinSize(minHeight = Hit.h2)
              .bottomHairline(Vitruvian.line)
              .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
              .padding(contentPadding),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    if (selectedRule != Color.Transparent) {
      Row(
          modifier =
              Modifier.width(2.dp)
                  .fillMaxHeight()
                  .defaultMinSize(minHeight = Hit.h2)
                  .background(selectedRule),
      ) {}
    }
    if (status != null) {
      Status(tone = status)
    }
    Column(modifier = Modifier.weight(1f)) {
      VText(
          text = title,
          style = VitruvianType.listTitle,
          color = titleColor,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
      )
      VText(
          text = subtitle,
          style = VitruvianType.listSub,
          color = Vitruvian.textDim,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
      )
    }
    trailing?.invoke(this)
  }
}
