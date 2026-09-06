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
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The status square's five states. */
public enum class StatusTone {
  Neutral,
  Ok,
  Warn,
  Crit,
  Run
}

private val STATUS_SQUARE = 7.dp
private val METER_HEIGHT = 6.dp
private val SEGBAR_HEIGHT = 20.dp
private val BAR_GAP = 2.dp

@Composable
private fun statusColor(tone: StatusTone): Color =
    when (tone) {
      StatusTone.Neutral -> Vitruvian.neutral500
      StatusTone.Ok -> Vitruvian.ok
      StatusTone.Warn -> Vitruvian.warn
      StatusTone.Crit -> Vitruvian.crit
      StatusTone.Run -> Vitruvian.accentText
    }

/**
 * `.status` - a 7 dp square, optionally followed by a mono uppercase caption.
 *
 * Passing a null [text] gives the bare square that leads every list row.
 */
@Composable
public fun Status(
    tone: StatusTone,
    modifier: Modifier = Modifier,
    text: String? = null,
    color: Color = Vitruvian.textDim,
) {
  val square = statusColor(tone)
  Row(
      modifier = modifier,
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Box(modifier = Modifier.size(STATUS_SQUARE).background(square))
    if (text != null) {
      VText(
          text = text.uppercase(),
          style = VitruvianType.status,
          color = color,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
          softWrap = false,
      )
    }
  }
}

/** `.metric` - label over value over delta, in a 5 dp stack. */
@Composable
public fun Metric(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    delta: String? = null,
    valueSize: TextUnit = 26.sp,
    valueColor: Color = LocalContentColor.current,
) {
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(Space.s2)) {
    Label(label)
    VText(
        text = value,
        style = VitruvianType.metricValue.copy(fontSize = valueSize),
        color = valueColor,
        maxLines = 1,
        softWrap = false,
    )
    if (delta != null) {
      VText(text = delta, style = VitruvianType.listSub, color = Vitruvian.textDim, maxLines = 1)
    }
  }
}

/**
 * `.meter` - a 6 dp track with an accent fill.
 *
 * [fraction] animates over [Duration.D4] linear, which is the rule every live value in this
 * language follows.
 */
@Composable
public fun Meter(
    fraction: Float,
    modifier: Modifier = Modifier,
    height: Dp = METER_HEIGHT,
    fillColor: Color = Vitruvian.accent,
) {
  val target = fraction.coerceIn(0f, 1f)
  val animated by
      animateFloatAsState(
          targetValue = target,
          animationSpec = tween(durationMillis = motion(Duration.D4), easing = LinearEasing),
          label = "meter",
      )
  Box(
      modifier =
          modifier
              .fillMaxWidth()
              .height(height)
              .background(Vitruvian.surface2)
              .border(1.dp, Vitruvian.line),
  ) {
    Box(modifier = Modifier.fillMaxHeight().fillMaxWidth(animated).background(fillColor))
  }
}

/** One cell of a [SegBar]. */
public enum class SegState {
  Empty,
  On,
  Warn
}

/** `.segbar` - the 16-segment memory-pressure readout. */
@Composable
public fun SegBar(
    segments: List<SegState>,
    modifier: Modifier = Modifier,
    height: Dp = SEGBAR_HEIGHT,
) {
  val colors = Vitruvian
  Row(
      modifier = modifier.fillMaxWidth().height(height),
      horizontalArrangement = Arrangement.spacedBy(BAR_GAP)) {
        segments.forEach { segment ->
          val (fill, border) =
              when (segment) {
                SegState.On -> colors.accent to colors.accent
                SegState.Warn -> colors.warn to colors.warn
                SegState.Empty -> colors.surface2 to colors.line
              }
          Box(
              modifier = Modifier.weight(1f).fillMaxHeight().background(fill).border(1.dp, border),
          )
        }
      }
}

/**
 * `.spark` - a bottom-aligned bar series.
 *
 * Each bar is an `accentQuiet` column capped with a 2 dp `accent` rule, and its height is its value
 * as a fraction of [max].
 */
@Composable
public fun Spark(
    values: List<Int>,
    modifier: Modifier = Modifier,
    height: Dp = 55.dp,
    max: Int = 100,
) {
  val colors = Vitruvian
  val accentRule = colors.accent
  Row(
      modifier = modifier.fillMaxWidth().height(height),
      horizontalArrangement = Arrangement.spacedBy(BAR_GAP),
      verticalAlignment = Alignment.Bottom,
  ) {
    values.forEach { value ->
      val fraction = (value.toFloat() / max.toFloat()).coerceIn(0f, 1f)
      Box(
          modifier =
              Modifier.weight(1f)
                  .fillMaxHeight(fraction)
                  .background(colors.accentQuiet)
                  .drawBehind {
                    drawRect(color = accentRule, size = Size(size.width, 2.dp.toPx()))
                  },
      )
    }
  }
}

/** One row of a [LogStream]. */
public data class LogEntry(val timestamp: String, val level: String, val message: String)

/** The level palette: ok / warn / err / info. */
@Composable
public fun logLevelColor(level: String): Color =
    when (level) {
      "ok" -> Vitruvian.ok
      "warn" -> Vitruvian.warn
      "err" -> Vitruvian.sanguineText
      "info" -> Vitruvian.accentText
      else -> Vitruvian.textDim
    }

/** `.log` - a 62 dp timestamp column, a 48 dp level column, then the message. */
@Composable
public fun LogStream(
    entries: List<LogEntry>,
    modifier: Modifier = Modifier,
) {
  val lineColor = Vitruvian.line
  val contentColor = LocalContentColor.current
  Column(modifier = modifier) {
    entries.forEach { entry ->
      Row(
          modifier = Modifier.fillMaxWidth().bottomHairline(lineColor).padding(vertical = 2.dp),
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        VText(
            text = entry.timestamp,
            modifier = Modifier.width(62.dp),
            style = VitruvianType.log,
            color = Vitruvian.textDim,
            maxLines = 1,
            softWrap = false,
        )
        VText(
            text = entry.level,
            modifier = Modifier.width(48.dp),
            style = VitruvianType.log,
            color = logLevelColor(entry.level),
            maxLines = 1,
            softWrap = false,
        )
        VText(
            text = entry.message,
            modifier = Modifier.weight(1f),
            style = VitruvianType.log,
            color = contentColor,
        )
      }
    }
  }
}

/** One column of a [VTable]. */
public data class TableColumn(val header: String, val alignEnd: Boolean = false)

/**
 * `.table` - label headers over a divider, mono 12 sp body cells over hairlines. Cell colour is
 * chosen by the caller, which is how the Mac screen turns CPU above 30% warn-coloured.
 */
@Composable
public fun VTable(
    columns: List<TableColumn>,
    rows: List<List<Pair<String, Color?>>>,
    modifier: Modifier = Modifier,
    weights: List<Float> = List(columns.size) { 1f },
) {
  val colors = Vitruvian
  val cellStyle: TextStyle = VitruvianType.log
  Column(modifier = modifier.fillMaxWidth()) {
    Row(
        modifier =
            Modifier.fillMaxWidth().bottomHairline(colors.divider).padding(vertical = Space.s3),
    ) {
      columns.forEachIndexed { index, column ->
        Label(
            text = column.header,
            modifier = Modifier.weight(weights[index]),
        )
      }
    }
    rows.forEach { row ->
      Row(
          modifier =
              Modifier.fillMaxWidth().bottomHairline(colors.line).padding(vertical = Space.s3),
      ) {
        row.forEachIndexed { index, (value, color) ->
          VText(
              text = value,
              modifier = Modifier.weight(weights[index]),
              style =
                  cellStyle.copy(
                      textAlign = if (columns[index].alignEnd) TextAlign.End else TextAlign.Start,
                  ),
              color = color ?: colors.text,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              softWrap = false,
          )
        }
      }
    }
  }
}
