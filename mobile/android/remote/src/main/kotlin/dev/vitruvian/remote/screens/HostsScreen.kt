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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.ButtonVariant
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
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.MetricsSource
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
    Label(text = "Hosts · ${state.hostRows.size}", modifier = Modifier.weight(1f))
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
  state.hostRows.forEach { host ->
    ListItem(
        title = host.name,
        subtitle = host.subtitle,
        status = host.tone,
        onClick = { state.selectHost(host.id) },
        selectedRule = if (state.selectedHost?.id == host.id) colors.accent else Color.Transparent,
    ) {
      Tag(text = host.tag, tone = host.tagTone)
    }
  }

  // The row that makes this a list rather than a setting. Adding a Mac selects
  // it, which is why it is a separate field from the one on the plate below:
  // typing here must never overwrite the address of the host in use.
  Row(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s3).fillMaxWidth(),
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    VInput(
        value = state.newHostDraft,
        onValueChange = state::updateNewHostDraft,
        modifier = Modifier.weight(1f),
        placeholder = "Add a Mac · 100.x.y.z or host.ts.net",
        imeAction = ImeAction.Go,
        onImeAction = state::addTypedHost,
    )
    VButton("Add", state::addTypedHost, enabled = state.newHostDraft.isNotBlank())
  }

  Box(modifier = Modifier.sectionPadding()) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item { AgentPlate(state) }
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

/**
 * The Mac agent: where it is, and whether it is answering.
 *
 * This is the only setting that changes what the dashboards show. The URL is applied on Connect,
 * not per keystroke, and the status line says plainly which of three states the numbers are in.
 */
@Composable
private fun AgentPlate(state: RemoteState) {
  val colors = Vitruvian
  val status =
      when (state.metricsSource) {
        MetricsSource.Simulated -> "no agent · dashboards are simulated"
        // The tag beside this already says live / unreachable; repeating the
        // word made "LIVE live". The text carries what the tag cannot.
        MetricsSource.Live ->
            "${state.agentHost?.hostname ?: "host"} · agent v${state.agentHost?.agentVersion ?: "?"}"
        MetricsSource.Unreachable -> state.agentError.ifBlank { "no answer yet" }
      }
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      // Says WHICH Mac is being edited. With more than one saved, a plate
      // headed "Mac agent" over a URL field is an invitation to retype the
      // wrong machine's address.
      Label("Mac agent · ${state.selectedHost?.alias?.ifBlank { null } ?: "none selected"}")
      VText(
          text = "Run the agent on the Mac and enter its Tailscale address. Edits the host above.",
          style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
          color = colors.textDim,
      )
      VInput(
          value = state.hostAliasDraft,
          onValueChange = state::updateHostAliasDraft,
          modifier = Modifier.fillMaxWidth(),
          placeholder = "name · atlas",
          imeAction = ImeAction.Done,
          onImeAction = state::saveAlias,
      )
      VInput(
          value = state.agentUrlDraft,
          onValueChange = state::updateAgentUrlDraft,
          modifier = Modifier.fillMaxWidth(),
          placeholder = "100.x.y.z or host.tailnet.ts.net",
      )
      // The Mac calls itself James-MacBook-Pro, which is what the top bar,
      // the rail and three screen headers would otherwise shout. A short
      // name here replaces it everywhere; blank falls back to the hostname.
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        VInput(
            value = state.hostAliasDraft,
            onValueChange = state::updateHostAliasDraft,
            modifier = Modifier.weight(1f),
            placeholder = "Name this Mac",
        )
        VButton("Save", state::saveHostAlias)
      }
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton(
            label = "Connect",
            onClick = {
              state.saveAlias()
              state.applyAgentUrl()
            },
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Primary,
        )
        VButton(
            label = "Forget",
            onClick = state::forgetAgent,
            modifier = Modifier.weight(1f),
            enabled = state.selectedHost != null,
        )
      }
      Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Tag(text = state.metricsSource.label, tone = state.metricsTagTone)
        VText(
            text = status,
            modifier = Modifier.weight(1f),
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
      }
    }
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
      Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Label(text = "Pair a new Mac", modifier = Modifier.weight(1f))
        // Whether this phone may act at all, and the only place that says so
        // before a button silently refuses.
        Tag(
            text = if (state.paired) "paired" else "not paired",
            tone = if (state.paired) TagTone.Ok else TagTone.Outline,
        )
      }
      // Paired: the code is noise until someone wants to pair again, so the
      // card says what it is paired with and offers to start over.
      var repair by remember { mutableStateOf(false) }
      if (state.paired && !repair) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VText(
              text = "This phone can act on ${state.agentHost?.hostname ?: "the Mac"}.",
              modifier = Modifier.weight(1f),
              style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
              color = colors.textDim,
          )
          VButton("Re-pair", { repair = true })
        }
        return@Column
      }
      VText(
          // The exact command, because a paraphrase of it is a command nobody
          // can run. The phone invents the code; the Mac is told what it is.
          text = "Run: bazel run //mobile/android/remote/macagent:pair -- ${state.pairDigits}",
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
          checked = state.wakeOnLan,
          onCheckedChange = state::updateWakeOnLan,
          label = "Send Wake-on-LAN when the Mac stops answering",
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
