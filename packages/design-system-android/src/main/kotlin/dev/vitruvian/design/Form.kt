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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * `.input` - a square field on `color.surface` with a divider border.
 *
 * Built on [BasicTextField] rather than a Material text field: this language has no floating label,
 * no indicator line and no rounded container.
 */
@Composable
public fun VInput(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    textStyle: TextStyle = VitruvianType.body,
    minHeight: Dp = Hit.h1,
    singleLine: Boolean = true,
    imeAction: ImeAction = ImeAction.Default,
    onImeAction: (() -> Unit)? = null,
) {
  val colors = Vitruvian
  BasicTextField(
      value = value,
      onValueChange = onValueChange,
      modifier =
          modifier
              .defaultMinSize(minHeight = minHeight)
              .background(colors.surface)
              .border(1.dp, colors.divider)
              .padding(horizontal = Space.s3, vertical = Space.s3),
      textStyle = textStyle.copy(color = colors.text),
      cursorBrush = SolidColor(colors.accentText),
      singleLine = singleLine,
      keyboardOptions = KeyboardOptions(imeAction = imeAction),
      keyboardActions = KeyboardActions { onImeAction?.invoke() },
      decorationBox = { inner ->
        Box(contentAlignment = Alignment.CenterStart) {
          if (value.isEmpty() && placeholder.isNotEmpty()) {
            VText(text = placeholder, style = textStyle, color = colors.textDim, maxLines = 1)
          }
          inner()
        }
      },
  )
}

/** A [VInput] under a `.label` caption. */
@Composable
public fun Field(
    label: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(Space.s2)) {
    Label(label)
    content()
  }
}

private val TRACK_WIDTH = 38.dp
private val TRACK_HEIGHT = 20.dp
private val THUMB = 14.dp
private val THUMB_INSET = 2.dp
private val THUMB_TRAVEL = 18.dp

/** `.switch` - a square 38x20 track with a 14 dp thumb that slides 18 dp. */
@Composable
public fun VSwitch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
  val colors = Vitruvian
  Row(
      modifier =
          modifier.defaultMinSize(minHeight = Hit.h1).clickable(enabled = enabled) {
            onCheckedChange(!checked)
          },
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Box(
        modifier =
            Modifier.width(TRACK_WIDTH)
                .height(TRACK_HEIGHT)
                .background(if (checked) colors.accentQuiet else colors.surface2)
                .border(1.dp, if (checked) colors.accent else colors.divider),
    ) {
      Box(
          modifier =
              Modifier.offset(
                      x = THUMB_INSET + if (checked) THUMB_TRAVEL else 0.dp,
                      y = THUMB_INSET,
                  )
                  .size(THUMB)
                  .background(if (checked) colors.accent else colors.textDim),
      )
    }
    VText(text = label, style = VitruvianType.body.copy(fontSize = FontSize.h5))
  }
}

/** One option of a [Segmented] control. */
public data class SegmentOption(val label: String, val selected: Boolean, val onSelect: () -> Unit)

/**
 * `.seg` - a bordered strip of mono options, the selected one filled with `accentQuiet` and
 * underlined by a 2 dp inset accent rule.
 */
@Composable
public fun Segmented(
    options: List<SegmentOption>,
    modifier: Modifier = Modifier,
) {
  val colors = Vitruvian
  Row(modifier = modifier.border(1.dp, colors.divider)) {
    options.forEachIndexed { index, option ->
      if (index > 0) {
        Box(modifier = Modifier.width(1.dp).height(Hit.h1).background(colors.divider))
      }
      Box(
          modifier =
              Modifier.defaultMinSize(minHeight = Hit.h1)
                  .background(if (option.selected) colors.accentQuiet else Color.Transparent)
                  .clickable(onClick = option.onSelect)
                  .drawBehind {
                    if (option.selected) {
                      drawRect(
                          color = colors.accent,
                          topLeft =
                              Offset(
                                  0f,
                                  size.height - 2.dp.toPx(),
                              ),
                          size =
                              Size(
                                  size.width,
                                  2.dp.toPx(),
                              ),
                      )
                    }
                  }
                  .padding(horizontal = Space.s4),
          contentAlignment = Alignment.Center,
      ) {
        VText(
            text = option.label.uppercase(),
            style = VitruvianType.status,
            color = if (option.selected) colors.text else colors.textDim,
            maxLines = 1,
            softWrap = false,
        )
      }
    }
  }
}
