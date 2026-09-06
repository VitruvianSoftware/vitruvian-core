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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.Plate
import dev.vitruvian.design.Rule
import dev.vitruvian.design.SegmentOption
import dev.vitruvian.design.Segmented
import dev.vitruvian.design.Space
import dev.vitruvian.design.Status
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.RemoteState

private val PAIR_CODE_SIZE = 38.sp
private val PAIR_CODE_TRACKING = 0.18.em
private val REFRESH_INTERVALS = listOf("1 s", "5 s", "30 s")

/**
 * Hosts: the paired Macs, pairing, connection settings and the macro list.
 *
 * Reached from the host chip in every posture, and the only screen the app shows at all until a Mac
 * is paired.
 */
@Composable
public fun ColumnScope.HostsScreen(state: RemoteState) {
  val colors = Vitruvian

  Row(
      modifier =
          Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3)
              .fillMaxWidth(),
      verticalAlignment = Alignment.Bottom,
  ) {
    Label(text = "Hosts · ${state.hosts.size}", modifier = Modifier.weight(1f))
    Status(tone = state.hostTone, text = state.connectionWord)
  }

  if (state.isUnpaired) {
    ListItem(
        title = "No hosts yet",
        subtitle = "pair one below",
        status = StatusTone.Neutral,
        titleColor = colors.textDim,
    )
  }
  state.hosts.forEach { host ->
    ListItem(
        title = host.name,
        subtitle = host.subtitle,
        status = host.tone,
        onClick = { state.selectHost(host.id) },
        selectedRule = if (state.selectedHost == host.id) colors.accent else Color.Transparent,
    ) {
      Tag(text = host.tag, tone = host.tagTone)
    }
  }

  Box(modifier = Modifier.sectionPadding()) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item { PairPlate(state) }
      item { ConnectionPlate(state) }
    }
  }

  Column(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s3).fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Macros · bound to scripts")
    state.macros.forEach { macro ->
      ListItem(
          title = macro.label,
          subtitle = macro.command,
          status = StatusTone.Ok,
          contentPadding = PaddingValues(vertical = Space.s3),
      ) {
        Tag(text = macro.kind.label, tone = TagTone.Outline)
      }
    }
    VButton(
        label = "+ New macro",
        onClick = state::openMacroEditor,
        modifier = Modifier.fillMaxWidth().padding(top = Space.s4),
        dashed = true,
    )
  }
}

/** The pairing plate - registration marks and a six-digit code. */
@Composable
private fun PairPlate(state: RemoteState) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth(), marks = true) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Label("Pair a new Mac")
      VText(
          text = "Run vitruvian-remote pair on the Mac and enter this code.",
          style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
          color = colors.textDim,
      )
      VText(
          text = state.pairCode,
          modifier = Modifier.fillMaxWidth().padding(vertical = Space.s3),
          style =
              VitruvianType.metricValue.copy(
                  fontSize = PAIR_CODE_SIZE,
                  letterSpacing = PAIR_CODE_TRACKING,
                  textAlign = TextAlign.Start,
              ),
      )
      Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        VText(
            text = "expires in ${state.pairTtl}",
            modifier = Modifier.weight(1f),
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
        VButton("New code", state::regeneratePairCode)
      }
    }
  }
}

/** Connection, appearance and refresh settings. */
@Composable
private fun ConnectionPlate(state: RemoteState) {
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s4),
    ) {
      Label("Connection")
      VSwitch(
          checked = state.tailscaleFirst,
          onCheckedChange = state::updateTailscaleFirst,
          label = "Tailscale first, LAN fallback",
      )
      VSwitch(
          checked = state.wakeOnLan,
          onCheckedChange = state::updateWakeOnLan,
          label = "Wake on LAN when unreachable",
      )
      VSwitch(
          checked = state.confirmDestructive,
          onCheckedChange = state::updateConfirmDestructive,
          label = "Typed confirmation for restart / destroy",
      )
      Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
      Label("Appearance")
      VSwitch(
          checked = !state.darkTheme,
          onCheckedChange = { state.toggleTheme() },
          label = "Parchment (light) theme",
      )
      Label("Refresh interval")
      Segmented(
          options =
              REFRESH_INTERVALS.map { interval ->
                SegmentOption(
                    label = interval,
                    selected = state.refreshInterval == interval,
                    onSelect = { state.updateRefreshInterval(interval) },
                )
              },
      )
    }
  }
}
