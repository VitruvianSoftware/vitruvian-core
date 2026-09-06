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

package dev.vitruvian.remote.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.LogStream
import dev.vitruvian.design.Meter
import dev.vitruvian.design.Metric
import dev.vitruvian.design.Plate
import dev.vitruvian.design.Space
import dev.vitruvian.design.Tag
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.Widget

/** `minmax(150dp, 1fr)` - the widget board. */
private val WIDGET_MIN = 150.dp

/** `minmax(110dp, 1fr)` - the quick-action board. */
private val ACTION_MIN = 110.dp

private const val RECENT_ROWS = 4
private val ADD_WIDGET_HEIGHT = 96.dp
private val CLOSE_BUTTON = 32.dp

/**
 * Home: the composable board.
 *
 * Widgets, what is running, the macros, and the tail of the event stream - the screen you land on
 * and the one edit mode reshapes.
 */
@Composable
public fun ColumnScope.HomeScreen(state: RemoteState) {
  val colors = Vitruvian
  Row(
      modifier =
          Modifier.fillMaxWidth()
              .padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.s1)) {
      Label(state.hostShortName)
      VText(
          text = "macOS 26.1 · Tailscale · 4 ms",
          style = VitruvianType.listSub,
          color = colors.textDim,
      )
    }
    VButton(
        label = if (state.editMode) "Done" else "Edit layout",
        onClick = state::toggleEditMode,
    )
  }

  Box(modifier = Modifier.padding(horizontal = Space.s4)) {
    AutoGrid(minItemWidth = WIDGET_MIN) {
      state.widgets.forEach { widget -> item { WidgetPlate(state = state, widget = widget) } }
      if (state.editMode) {
        item {
          Plate(
              modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = ADD_WIDGET_HEIGHT),
              dashed = true,
          ) {
            VButton(
                label = "+ Add widget",
                onClick = state::restoreWidgets,
                modifier = Modifier.fillMaxWidth().align(Alignment.Center),
                borderColor = Color.Transparent,
                contentColor = colors.textDim,
            )
          }
        }
      }
    }
  }

  Label(
      text = "Running now",
      modifier =
          Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
  )
  state.runningNow.forEach { item ->
    ListItem(
        title = item.title,
        subtitle = item.subtitle,
        status = item.tone,
        onClick = { state.openModule(item.moduleId) },
    ) {
      Tag(text = item.tag, tone = item.tagTone)
    }
  }

  Label(
      text = "Quick actions",
      modifier =
          Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
  )
  Box(modifier = Modifier.padding(horizontal = Space.s4)) {
    AutoGrid(minItemWidth = ACTION_MIN) {
      state.macros.forEach { macro ->
        item {
          VButton(
              label = macro.label,
              onClick = { state.runMacro(macro) },
              modifier = Modifier.fillMaxWidth(),
              contentPadding =
                  PaddingValues(
                      horizontal = Space.s3,
                  ),
          )
        }
      }
      item {
        VButton(
            label = "+ Macro",
            onClick = state::openMacroEditor,
            modifier = Modifier.fillMaxWidth(),
            dashed = true,
            contentColor = colors.textDim,
        )
      }
    }
  }

  Label(
      text = "Recent",
      modifier =
          Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
  )
  LogStream(
      entries = state.logs.take(RECENT_ROWS),
      modifier = Modifier.padding(horizontal = Space.s4),
  )
}

/**
 * One widget: a metric over a meter, inside a plate.
 *
 * In edit mode it grows a close button pinned to its top-right corner, overlapping the plate's own
 * border by a pixel exactly as the CSS does.
 */
@Composable
private fun WidgetPlate(state: RemoteState, widget: Widget) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Metric(
          label = widget.label,
          value = widget.value,
          delta = widget.sub,
          valueColor = if (widget.warn) colors.warn else colors.text,
      )
      Meter(
          fraction = widget.percent / 100f,
          fillColor = if (widget.warn) colors.warn else colors.accent,
      )
    }
    if (state.editMode) {
      VButton(
          label = "×",
          onClick = { state.hideWidget(widget.id) },
          modifier = Modifier.align(Alignment.TopEnd).size(CLOSE_BUTTON),
          contentPadding = PaddingValues(0.dp),
      )
    }
  }
}
