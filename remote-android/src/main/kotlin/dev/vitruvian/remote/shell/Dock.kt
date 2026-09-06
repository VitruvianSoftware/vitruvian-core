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

package dev.vitruvian.remote.shell

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Label
import dev.vitruvian.design.LogStream
import dev.vitruvian.design.Meter
import dev.vitruvian.design.Space
import dev.vitruvian.design.Status
import dev.vitruvian.design.Terminal
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.screens.Trackpad
import dev.vitruvian.remote.state.DialogKind
import dev.vitruvian.remote.state.RemoteState

/** The dock's terminal is bottom-anchored and shows the last eight lines. */
private const val DOCK_TAIL = 8
private val DOCK_TERMINAL_HEIGHT = 200.dp
private val DOCK_CONTROLS_WIDTH = 200.dp

/**
 * The dock pane.
 *
 * On every screen but Remote-in-tabletop it is the console: terminal, a command line, every macro
 * as a quick action, and the tail of the event stream. In tabletop on Remote it becomes the
 * trackpad and the media controls instead, so the lower half of the device is where your hands are.
 */
@Composable
public fun Dock(
    state: RemoteState,
    showsTrackpad: Boolean,
    modifier: Modifier = Modifier,
) {
  if (showsTrackpad) {
    TrackpadDock(state = state, modifier = modifier)
  } else {
    ConsoleDock(state = state, modifier = modifier)
  }
}

@Composable
private fun TrackpadDock(state: RemoteState, modifier: Modifier = Modifier) {
  Row(
      modifier = modifier.fillMaxSize().padding(Space.s4),
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Trackpad(
        state = state,
        modifier = Modifier.weight(1f).fillMaxHeight(),
        captionPrefix = "Trackpad · ",
    )
    Column(
        modifier = Modifier.width(DOCK_CONTROLS_WIDTH).fillMaxHeight(),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      VButton("Click", state::click, modifier = Modifier.fillMaxWidth())
      VButton("Right", state::rightClick, modifier = Modifier.fillMaxWidth())
      VButton(
          label = "Keys",
          onClick = state::toggleKeyboard,
          modifier = Modifier.fillMaxWidth(),
          contentColor = if (state.keyboardOpen) Vitruvian.accentText else null,
      )
      Box(modifier = Modifier.weight(1f))
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s2)) {
        VButton("⏮", state::previousTrack, modifier = Modifier.weight(1f))
        VButton(
            label = if (state.playing) "⏸" else "▶",
            onClick = state::togglePlay,
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Primary,
        )
        VButton("⏭", state::nextTrack, modifier = Modifier.weight(1f))
      }
      Row(
          horizontalArrangement = Arrangement.spacedBy(Space.s2),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        VButton("−", { state.nudgeVolume(-VOLUME_STEP) }, modifier = Modifier.width(44.dp))
        Meter(
            fraction = state.volume / 100f,
            modifier = Modifier.weight(1f),
            height = 8.dp,
        )
        VButton("+", { state.nudgeVolume(VOLUME_STEP) }, modifier = Modifier.width(44.dp))
      }
    }
  }
}

@Composable
private fun ConsoleDock(state: RemoteState, modifier: Modifier = Modifier) {
  Column(modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
    Row(
        modifier =
            Modifier.fillMaxWidth()
                .padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Label(text = "Console · ${state.hostShortName}", modifier = Modifier.weight(1f))
      Status(tone = state.hostTone, text = state.connectionWord)
    }
    Column(
        modifier = Modifier.padding(horizontal = Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Terminal(
          lines = state.terminal.takeLast(DOCK_TAIL),
          modifier = Modifier.height(DOCK_TERMINAL_HEIGHT),
          bottomAnchored = true,
      )
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VInput(
            value = state.command,
            onValueChange = state::setCommand,
            modifier = Modifier.weight(1f),
            placeholder = "command…",
            textStyle = VitruvianType.mono,
            imeAction = ImeAction.Go,
            onImeAction = state::runCommand,
        )
        VButton("Run", state::runCommand, variant = ButtonVariant.Primary)
      }
    }
    Label(
        text = "Quick actions",
        modifier =
            Modifier.padding(
                start = Space.s4,
                end = Space.s4,
                top = Space.s5,
                bottom = Space.s3,
            ),
    )
    Column(modifier = Modifier.padding(horizontal = Space.s4)) {
      AutoGrid(minItemWidth = DOCK_ACTION_MIN) {
        state.macros.forEach { macro ->
          item {
            VButton(
                label = macro.label,
                onClick = { state.runMacro(macro) },
                modifier = Modifier.fillMaxWidth(),
            )
          }
        }
        item { VButton("Lock", state::lock, modifier = Modifier.fillMaxWidth()) }
        item {
          VButton(
              label = "Restart",
              onClick = { state.openDialog(DialogKind.Restart) },
              modifier = Modifier.fillMaxWidth(),
              variant = ButtonVariant.Danger,
          )
        }
      }
    }
    Label(
        text = "Event stream",
        modifier =
            Modifier.padding(
                start = Space.s4,
                end = Space.s4,
                top = Space.s5,
                bottom = Space.s3,
            ),
    )
    LogStream(
        entries = state.logs.take(DOCK_LOG_ROWS),
        modifier = Modifier.padding(horizontal = Space.s4).heightIn(min = 0.dp),
    )
    Box(modifier = Modifier.height(Space.s5))
  }
}

private const val VOLUME_STEP = 6
private const val DOCK_LOG_ROWS = 4

/** Two columns in a 300 dp dock; the grid falls back to one when it is narrower. */
private val DOCK_ACTION_MIN = 130.dp
