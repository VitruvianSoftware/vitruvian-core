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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Kbd
import dev.vitruvian.design.Label
import dev.vitruvian.design.LogStream
import dev.vitruvian.design.Space
import dev.vitruvian.design.Status
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.Terminal
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.overlays.DictateButton
import dev.vitruvian.remote.state.RemoteState

private val TERMINAL_MIN = 220.dp
private val TERMINAL_MAX = 380.dp

/**
 * Console: the full-height shell.
 *
 * The one screen the dock never flanks - when you are here the console already has the whole pane,
 * so a second copy of it beside itself would be absurd.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
public fun ColumnScope.ConsoleScreen(state: RemoteState) {
  Row(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    // Not "ssh · james@atlas": there is no SSH session. Commands go to the
    // agent, which runs them in a login zsh, and the difference matters the
    // moment one of them needs a TTY.
    Label(text = state.consoleSubtitle, modifier = Modifier.weight(1f))
    Status(
        tone = if (state.paired) StatusTone.Ok else StatusTone.Neutral,
        text = if (state.paired) "paired" else "not paired",
    )
  }
  Column(
      modifier = Modifier.padding(horizontal = Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    // An empty terminal is a blinking cursor and nothing else, which reads
    // as a console that failed to connect rather than one nobody has used.
    if (state.terminal.isEmpty()) {
      VText(
          text = "Run a command on the Mac. Output lands here.",
          modifier = Modifier.padding(vertical = Space.s3),
          style = VitruvianType.listSub,
          color = Vitruvian.textDim,
      )
    }
    Terminal(
        lines = state.terminal.toList(),
        modifier =
            Modifier.heightIn(min = TERMINAL_MIN, max = TERMINAL_MAX)
                .verticalScroll(rememberScrollState()),
        cursor = true,
    )
    Row(
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      VInput(
          value = state.command,
          onValueChange = state::updateCommand,
          modifier = Modifier.weight(1f),
          placeholder = "command…",
          textStyle = VitruvianType.mono.copy(fontSize = 14.sp),
          imeAction = ImeAction.Go,
          onImeAction = state::runCommand,
      )
      // Appends rather than replaces: dictation is usually the argument to a
      // command that has already been typed or tapped in from a chip.
      DictateButton(state) { spoken ->
        state.updateCommand(
            listOf(state.command.trim(), spoken).filter { it.isNotBlank() }.joinToString(" "))
      }
      // Run becomes Stop while something is in flight. Two buttons would leave
      // Run live during a build, and a second stream into one terminal
      // interleaves output with nothing to say which line belongs to which.
      if (state.commandRunning) {
        VButton("Stop", state::stopCommand, variant = ButtonVariant.Danger)
      } else {
        VButton("Run", state::runCommand, variant = ButtonVariant.Primary)
      }
    }
    if (state.commandRunning) {
      // The honest version of a spinner: it names the command that is holding
      // the console, so a terminal that has gone quiet is distinguishable from
      // one that has finished.
      VText(
          text = "running… ${state.runningLabel}",
          style = VitruvianType.listSub,
          color = Vitruvian.textDim,
      )
    }
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(Space.s2),
        verticalArrangement = Arrangement.spacedBy(Space.s2),
    ) {
      state.recentCommands.forEach { command ->
        Kbd(text = command, onClick = { state.updateCommand(command) })
      }
    }
  }
  Label(text = "Event stream", modifier = Modifier.sectionPadding())
  LogStream(
      entries = state.logs.toList(),
      modifier = Modifier.padding(horizontal = Space.s4),
  )
}
