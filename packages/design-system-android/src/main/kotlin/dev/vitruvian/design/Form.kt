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
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

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
        Box(contentAlignment = if (singleLine) Alignment.CenterStart else Alignment.TopStart) {
          if (value.isEmpty() && placeholder.isNotEmpty()) {
            VText(
                text = placeholder,
                style = textStyle,
                color = colors.textDim,
                maxLines = if (singleLine) 1 else Int.MAX_VALUE,
            )
          }
          inner()
        }
      },
  )
}

/** `.textarea` - a multi-line square input field. */
@Composable
public fun VTextarea(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    textStyle: TextStyle = VitruvianType.body,
    minHeight: Dp = 96.dp,
) {
  VInput(
      value = value,
      onValueChange = onValueChange,
      modifier = modifier.fillMaxWidth(),
      placeholder = placeholder,
      textStyle = textStyle,
      minHeight = minHeight,
      singleLine = false,
  )
}

/** A form control under a `.label` caption, with optional [hint] or [error] message. */
@Composable
public fun Field(
    label: String,
    modifier: Modifier = Modifier,
    hint: String? = null,
    error: String? = null,
    content: @Composable () -> Unit,
) {
  val colors = Vitruvian
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(Space.s2)) {
    Label(label)
    content()
    if (error != null) {
      VText(text = error, style = VitruvianType.listSub, color = colors.sanguineText)
    } else if (hint != null) {
      VText(text = hint, style = VitruvianType.listSub, color = colors.textDim)
    }
  }
}

private val TRACK_WIDTH = 38.dp
private val TRACK_HEIGHT = 20.dp
private val THUMB = 14.dp
private val THUMB_INSET = 2.dp
private val THUMB_TRAVEL = 18.dp
private val CHECK_BOX_SIZE = 18.dp
private val CHECK_MARK_SIZE = 8.dp

/**
 * `.switch` - a square 38x20 track with a 14 dp thumb that slides 18 dp. [label] is optional: leave
 * it empty for a bare switch in a list row's trailing slot.
 */
@Composable
public fun VSwitch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    label: String = "",
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
    // No label: a bare track for a list row's trailing slot, with no gap after it.
    if (label.isNotEmpty()) {
      VText(text = label, style = VitruvianType.body.copy(fontSize = FontSize.h5))
    }
  }
}

/** `.check` - a square 18 dp checkbox with an 8 dp accent inner block when checked. */
@Composable
public fun VCheckbox(
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
            Modifier.size(CHECK_BOX_SIZE)
                .background(if (checked) colors.accentQuiet else colors.surface)
                .border(1.dp, if (checked) colors.accent else colors.divider),
        contentAlignment = Alignment.Center,
    ) {
      if (checked) {
        Box(modifier = Modifier.size(CHECK_MARK_SIZE).background(colors.accent))
      }
    }
    VText(text = label, style = VitruvianType.body.copy(fontSize = FontSize.h5))
  }
}

/** `.radio` - an 18 dp circular indicator with an 8 dp accent center dot when selected. */
@Composable
public fun VRadio(
    selected: Boolean,
    onClick: () -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
  val colors = Vitruvian
  Row(
      modifier =
          modifier
              .defaultMinSize(minHeight = Hit.h1)
              .clickable(enabled = enabled, onClick = onClick),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Box(
        modifier =
            Modifier.size(CHECK_BOX_SIZE).drawBehind {
              val stroke = 1.dp.toPx()
              drawOval(
                  color = if (selected) colors.accentQuiet else colors.surface,
              )
              drawOval(
                  color = if (selected) colors.accent else colors.divider,
                  topLeft = Offset(stroke / 2f, stroke / 2f),
                  size = Size(size.width - stroke, size.height - stroke),
                  style = Stroke(width = stroke),
              )
              if (selected) {
                val dot = CHECK_MARK_SIZE.toPx()
                drawOval(
                    color = colors.accent,
                    topLeft = Offset((size.width - dot) / 2f, (size.height - dot) / 2f),
                    size = Size(dot, dot),
                )
              }
            },
    )
    VText(text = label, style = VitruvianType.body.copy(fontSize = FontSize.h5))
  }
}

/** One option of a [VSelect] control. */
public data class SelectOption(val value: String, val label: String)

/** `.select` - a square selector row that opens a modal option sheet. */
@Composable
public fun VSelect(
    value: String,
    options: List<SelectOption>,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    title: String = "Select option",
) {
  val colors = Vitruvian
  var open by remember { mutableStateOf(false) }
  val activeLabel = options.firstOrNull { it.value == value }?.label ?: value

  Row(
      modifier =
          modifier
              .fillMaxWidth()
              .defaultMinSize(minHeight = Hit.h1)
              .background(colors.surface)
              .border(1.dp, colors.divider)
              .clickable { open = true }
              .padding(horizontal = Space.s3, vertical = Space.s3),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    // Weighted, so a long value ellipsises instead of pushing the chevron out of the row.
    VText(
        text = activeLabel,
        modifier = Modifier.weight(1f),
        style = VitruvianType.body,
        color = colors.text,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
    VIcon(path = VitruvianIcons.CHEVRON_DOWN, iconSize = 16.dp, color = colors.textDim)
  }

  if (open) {
    OptionSheet(
        title = title,
        options = options.map { SheetOption(label = it.label, selected = it.value == value) },
        onSelect = { index -> onValueChange(options[index].value) },
        onDismissRequest = { open = false },
    )
  }
}

/** `.slider` - a linear range control with a 6 dp track and a 14 dp square thumb. */
@Composable
public fun VSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    valueRange: ClosedFloatingPointRange<Float> = 0f..100f,
    label: String? = null,
    unit: String = "",
    formatValue: (Float) -> String = { it.toInt().toString() },
) {
  val colors = Vitruvian
  val span = (valueRange.endInclusive - valueRange.start).coerceAtLeast(0.0001f)
  val fraction = ((value - valueRange.start) / span).coerceIn(0f, 1f)
  var widthPx by remember { mutableStateOf(1f) }

  Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.s2)) {
    if (label != null) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Label(text = label)
        VText(
            text = "${formatValue(value)}$unit",
            style = VitruvianType.mono,
            color = colors.accentText,
        )
      }
    }
    BoxWithConstraints(
        modifier =
            Modifier.fillMaxWidth()
                .height(Hit.h1)
                .onSizeChanged { widthPx = it.width.toFloat().coerceAtLeast(1f) }
                .pointerInput(valueRange) {
                  detectTapGestures { offset ->
                    val nextFraction = (offset.x / widthPx).coerceIn(0f, 1f)
                    onValueChange(valueRange.start + nextFraction * span)
                  }
                }
                .pointerInput(valueRange) {
                  detectHorizontalDragGestures { change, _ ->
                    change.consume()
                    val nextFraction = (change.position.x / widthPx).coerceIn(0f, 1f)
                    onValueChange(valueRange.start + nextFraction * span)
                  }
                },
        contentAlignment = Alignment.CenterStart,
    ) {
      val trackTravel = (maxWidth - THUMB).coerceAtLeast(0.dp)
      Box(
          modifier =
              Modifier.fillMaxWidth()
                  .height(6.dp)
                  .background(colors.surface2)
                  .border(1.dp, colors.line),
      ) {
        Box(modifier = Modifier.fillMaxHeight().fillMaxWidth(fraction).background(colors.accent))
      }
      Box(
          modifier =
              Modifier.offset(x = trackTravel * fraction)
                  .size(THUMB)
                  .background(colors.accent)
                  .border(1.dp, colors.bg),
      )
    }
  }
}

/**
 * A clipboard action button that copies [value] and switches its caption to `"COPIED"` for 1.5s.
 */
@Composable
public fun CopyButton(
    value: String,
    modifier: Modifier = Modifier,
    label: String = "Copy",
    copiedLabel: String = "Copied",
) {
  val clipboard = LocalClipboardManager.current
  val colors = Vitruvian
  var copied by remember { mutableStateOf(false) }

  LaunchedEffect(copied) {
    if (copied) {
      delay(1500)
      copied = false
    }
  }

  VButton(
      label = if (copied) copiedLabel else label,
      onClick = {
        clipboard.setText(AnnotatedString(value))
        copied = true
      },
      modifier = modifier,
      variant = ButtonVariant.Secondary,
      borderColor = if (copied) colors.accent else colors.divider,
      contentColor = if (copied) colors.accentText else colors.text,
      contentPadding = PaddingValues(horizontal = Space.s3),
  )
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
