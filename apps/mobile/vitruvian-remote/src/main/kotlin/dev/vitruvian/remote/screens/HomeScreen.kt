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

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Hit
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.LogStream
import dev.vitruvian.design.Meter
import dev.vitruvian.design.Metric
import dev.vitruvian.design.OptionSheet
import dev.vitruvian.design.Plate
import dev.vitruvian.design.SheetOption
import dev.vitruvian.design.Space
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.Tag
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VIcon
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianIcons
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.shell.LocalShowDock
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.Screen
import dev.vitruvian.remote.state.Widget

/** `minmax(150dp, 1fr)` - the widget board. */
private val WIDGET_MIN = 150.dp

/**
 * `minmax(160dp, 1fr)` - the quick-action board.
 *
 * Two to a row on a folded phone. At 110 dp it fitted three, each about 120 dp, and a button label
 * is one uppercase line: "DEPLOY STAGING" and "SCREENSHOT → CLIP" were cut to "DEPLOY STAGI…".
 * Wider screens still get as many columns as fit.
 */
private val ACTION_MIN = 160.dp

private const val RECENT_ROWS = 4
private const val STALE_WIDGET_ALPHA = 0.55f
private val ADD_WIDGET_HEIGHT = 96.dp
private val CLOSE_BUTTON = Hit.h1

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
      Row(
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Label(state.hostShortName)
        // Measuring or pretending. A dashboard that cannot say which is
        // worse than either, so this is never hidden.
        Tag(text = state.metricsTagLabel, tone = state.metricsTagTone)
      }
      VText(
          text = state.hostSubline,
          style = VitruvianType.listSub,
          color = colors.textDim,
      )
    }
    VButton(
        label = if (state.editMode) "Done" else "Edit layout",
        onClick = state::toggleEditMode,
    )
  }

  // In demo mode, keep a pointer back to pairing a real Mac.
  if (state.isDemoMode) {
    Box(modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s2)) {
      Plate(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(Space.s4),
            verticalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          Label("Connect your Mac")
          VText(
              text = "Run the Mac helper on your Mac, then enter your Mac's address.",
              style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
              color = colors.textDim,
          )
          VButton(
              label = "Set up",
              onClick = { state.go(Screen.Hosts) },
              variant = ButtonVariant.Primary,
          )
        }
      }
    }
  }

  var showAddWidgetSheet by remember { mutableStateOf(false) }
  val hiddenOptions = state.hiddenWidgetOptions

  if (!state.isDemoMode && state.widgets.isEmpty() && !state.editMode) {
    if (state.hostPhase == Derive.HostPhase.Asking) {
      ListItem(
          title = "Checking…",
          subtitle = "Waiting for first reading from Mac",
          status = StatusTone.Neutral,
      )
    } else {
      val detail =
          state.agentError.takeIf { it.isNotBlank() }?.let { Derive.stripRawErrorPrefix(it) }
      ListItem(
          title = Derive.unansweredHostLine(state.hostShortName),
          subtitle = detail ?: "No reply from your Mac.",
          status = StatusTone.Crit,
      )
    }
  } else {
    Box(modifier = Modifier.padding(horizontal = Space.s4)) {
      AutoGrid(minItemWidth = WIDGET_MIN) {
        state.widgets.forEach { widget -> item { WidgetPlate(state = state, widget = widget) } }
        if (Derive.shouldShowAddWidget(state.editMode, state.hiddenWidgets.toSet())) {
          item {
            Plate(
                modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = ADD_WIDGET_HEIGHT),
                dashed = true,
            ) {
              VButton(
                  label = "+ Add widget",
                  onClick = { showAddWidgetSheet = true },
                  modifier = Modifier.fillMaxWidth().align(Alignment.Center),
                  borderColor = Color.Transparent,
                  contentColor = colors.textDim,
              )
            }
          }
        }
      }
    }
  }

  if (showAddWidgetSheet && hiddenOptions.isNotEmpty()) {
    OptionSheet(
        title = "Add widget",
        options = hiddenOptions.map { option -> SheetOption(label = option.label) },
        onSelect = { index ->
          hiddenOptions.getOrNull(index)?.let { state.showWidget(it.id) }
          showAddWidgetSheet = false
        },
        onDismissRequest = { showAddWidgetSheet = false },
    )
  }

  Label(
      text = "Running now",
      modifier =
          Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
  )
  state.runningNowEmpty?.let { emptyMsg ->
    ListItem(
        title = emptyMsg,
        subtitle =
            if (emptyMsg == "Checking…") "Waiting for first reply from Mac"
            else "No active sessions or jobs",
        status = StatusTone.Neutral,
    )
  }
  state.runningNow.forEach { item ->
    val navigable = item.moduleId.isNotBlank()
    ListItem(
        title = item.title,
        subtitle = item.subtitle,
        status = item.tone,
        modifier =
            if (state.isStaleReading && navigable) Modifier.alpha(STALE_WIDGET_ALPHA) else Modifier,
        // Opens that module's dashboard on Apps; the chevron says the row
        // goes somewhere, which a status row otherwise gives no hint of.
        onClick = if (navigable) ({ state.openModule(item.moduleId) }) else null,
    ) {
      Tag(text = item.tag, tone = item.tagTone)
      if (navigable) {
        VText(text = "›", style = VitruvianType.listTitle, color = colors.textDim)
      }
    }
  }

  // When the dock is beside the content it already lists every macro; the
  // same buttons a second time under the dashboard read as a layout bug.
  if (!LocalShowDock.current) {
    Label(
        text =
            if (state.actsNeedPairing) "Quick actions · pair this phone to run them"
            else "Quick actions",
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
                enabled = !state.actsNeedPairing,
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
  }

  // The dock beside the content already shows the event stream.
  if (!LocalShowDock.current) {
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
  Plate(modifier = Modifier.fillMaxWidth().alpha(if (widget.stale) STALE_WIDGET_ALPHA else 1f)) {
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
      // "ok" has no percentage; a meter under it drew an empty bar that
      // read as a broken gauge. Only numbers get a bar.
      if (widget.value.any { it.isDigit() })
          Meter(
              fraction = widget.percent / 100f,
              fillColor = if (widget.warn) colors.warn else colors.accent,
          )
      else Box(modifier = Modifier.height(METER_SLOT))
    }
    if (state.editMode) {
      Box(
          modifier =
              Modifier.align(Alignment.TopEnd)
                  .size(CLOSE_BUTTON)
                  .clickable(
                      role = Role.Button,
                      onClickLabel = "Remove widget",
                      onClick = { state.hideWidget(widget.id) },
                  ),
          contentAlignment = Alignment.Center,
      ) {
        VIcon(
            path = VitruvianIcons.CLOSE,
            color = colors.textDim,
            contentDescription = "Remove widget",
        )
      }
    }
  }
}

/** Reserved where a widget has no bar, so a row of tiles keeps one baseline. */
private val METER_SLOT = 8.dp
