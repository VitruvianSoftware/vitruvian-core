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
import androidx.compose.runtime.LaunchedEffect
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
import dev.vitruvian.remote.state.Format
import dev.vitruvian.remote.state.MetricsSource
import dev.vitruvian.remote.state.RemoteState
import java.time.Instant

private val PAIR_CODE_SIZE = 38.sp
private val PAIR_CODE_TRACKING = 0.18.em
private val REFRESH_INTERVALS = listOf("1 s", "5 s", "30 s")

/**
 * How many audit rows the plate draws. The last 100 are kept; 20 is what fits and is worth reading.
 */
private const val AUDIT_SHOWN = 20

/**
 * Hosts: the paired Macs, pairing, connection settings and the macro list.
 *
 * Reached from the host chip in every posture, and the only screen the app shows at all until a Mac
 * is paired.
 */
@Composable
public fun ColumnScope.HostsScreen(state: RemoteState) {
  val colors = Vitruvian

  // The permission answers change while this app is in the background -- the
  // user grants one from the system settings, or revokes it -- so they are
  // re-read every time the screen appears rather than once at construction.
  LaunchedEffect(Unit) { state.refreshBridgePermissions() }

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
      item { PhoneBridgePlate(state) }
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
              state.saveHostAlias()
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
      // Where the Mac's own notifications go, and a way to prove the whole
      // path rather than the flags. The agent publishes to ntfy itself; if
      // this is not configured, nothing the Mac notices ever reaches a phone
      // that is not looking at the app.
      Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        VText(
            text = state.notifyLine,
            modifier = Modifier.weight(1f),
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
        VButton("Test push", state::testPush, enabled = state.paired)
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

/**
 * The phone bridge: the switch, the trust window, the permissions and what agents have done.
 *
 * Everything on this plate is a claim about a capability that is otherwise invisible. A phone that
 * has quietly stopped answering the Mac, a trust window that is still open an hour after you forgot
 * about it, and a tool that cannot run because one permission was never granted all look exactly
 * like a working bridge from the Mac's side -- so each of them is a line here, with the next step
 * written out.
 */
@Composable
private fun PhoneBridgePlate(state: RemoteState) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Label(text = "Phone bridge", modifier = Modifier.weight(1f))
        Tag(
            text = if (state.bridgeLinked) "linked" else "not linked",
            tone = if (state.bridgeLinked) TagTone.Ok else TagTone.Outline,
        )
      }
      VText(
          text =
              "Agents on the Mac get a phone MCP server: messages, contacts, calls, location. " +
                  "Every call is listed below.",
          style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
          color = colors.textDim,
      )
      VSwitch(
          checked = state.bridgeEnabled,
          onCheckedChange = state::updateBridgeEnabled,
          label = "Run the bridge",
          enabled = state.bridgeAvailable,
      )
      // The link's own words. "not linked" with no reason is the one state
      // nobody can act on, so the reason is always on screen.
      VText(
          text = if (state.bridgeLinked) "linked to the Mac agent" else state.bridgeLinkStatus,
          style = VitruvianType.listSub,
          color = colors.textDim,
      )

      Rule(modifier = Modifier.fillMaxWidth().height(1.dp))

      // The trust window. Open, it says how long is left and offers to close
      // it; shut, it is one button and the plainest possible label.
      if (state.trustOpen) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VText(
              text = "Agents trusted · ${state.trustRemaining}",
              modifier = Modifier.weight(1f),
              style = VitruvianType.listSub,
          )
          VButton("End trust", state::endTrust)
        }
      } else {
        VButton(
            label = "Trust agents for 1 hour",
            onClick = state::trustAgents,
            modifier = Modifier.fillMaxWidth(),
            enabled = state.bridgeAvailable,
        )
        VText(
            text =
                "Off, screen control and opening apps are refused and texts and calls ask here " +
                    "first.",
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
      }

      // The pending approval, in the app as well as in the shade: a
      // notification that was swiped away would otherwise leave the agent
      // waiting out the whole minute with nowhere to say yes.
      state.pendingApproval?.let { pending ->
        Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
        Label("Waiting for you")
        VText(text = "Agent wants to: ${pending.question}", style = VitruvianType.listSub)
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
          VButton(
              label = "Approve",
              onClick = state::approvePending,
              modifier = Modifier.weight(1f),
              variant = ButtonVariant.Primary,
          )
          VButton(
              label = "Deny",
              onClick = state::denyPending,
              modifier = Modifier.weight(1f),
              variant = ButtonVariant.Danger,
          )
        }
      }

      Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
      Label("Permissions")
      state.bridgePermissions.forEach { permission ->
        ListItem(
            title = permission.label,
            // Never blank: an ungranted row says which tools it stops and how
            // to fix it, because the alternative is a tool that returns
            // nothing on the Mac for no visible reason.
            subtitle =
                if (permission.granted) permission.tools else "${permission.tools} · not granted",
            status = if (permission.granted) StatusTone.Ok else StatusTone.Warn,
            contentPadding = PaddingValues(vertical = Space.s3),
        ) {
          if (permission.granted) {
            Tag(text = "granted", tone = TagTone.Ok)
          } else if (permission.grantable) {
            VButton("Grant", { state.grantBridgePermission(permission.id) })
          } else {
            // Part 2's rows land here: notification access and the
            // accessibility service are granted in Settings, not by a dialog,
            // so the row carries the path instead of a button.
            Tag(text = "in Settings", tone = TagTone.Outline)
          }
        }
      }

      Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
      Label("Recent calls · ${state.bridgeAudit.size} kept")
      if (state.bridgeAudit.isEmpty()) {
        VText(
            text = "No agent has called a tool on this phone yet.",
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
      }
      state.bridgeAudit.take(AUDIT_SHOWN).forEach { entry ->
        ListItem(
            title = entry.tool,
            subtitle =
                Format.parts(
                    Format.relativeTime(
                        Instant.ofEpochMilli(entry.atMs).toString(), state.bridgeNowMs),
                    entry.arguments,
                    entry.approver,
                ),
            status = if (entry.outcome == "ok") StatusTone.Ok else StatusTone.Warn,
            contentPadding = PaddingValues(vertical = Space.s3),
        ) {
          Tag(
              text = entry.outcome,
              tone = if (entry.outcome == "ok") TagTone.Ok else TagTone.Outline)
        }
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
