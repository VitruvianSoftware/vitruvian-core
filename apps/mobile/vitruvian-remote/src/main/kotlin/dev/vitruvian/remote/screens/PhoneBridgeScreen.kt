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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.Plate
import dev.vitruvian.design.Rule
import dev.vitruvian.design.Space
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.Format
import dev.vitruvian.remote.state.RemoteState
import java.time.Instant

/** How many audit rows the Phone Bridge page displays. */
private const val BRIDGE_AUDIT_SHOWN = 20

/**
 * Phone Bridge: toggle, permissions and call log for AI agent tools on this phone.
 *
 * Reached from Settings -> Phone Bridge rather than cluttering the main settings list.
 */
@Composable
public fun ColumnScope.PhoneBridgeScreen(state: RemoteState) {
  val colors = Vitruvian

  LaunchedEffect(Unit) {
    state.refreshBridgePermissions()
    state.refreshNotificationPermission()
  }

  Box(modifier = Modifier.sectionPadding()) {
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
          Label(text = "Phone Bridge", modifier = Modifier.weight(1f))
          Tag(
              text = if (state.bridgeLinked) "linked" else "not linked",
              tone =
                  when {
                    state.bridgeLinked -> TagTone.Ok
                    Derive.bridgeProblemIsBannerWorthy(state.bridgeProblem) -> TagTone.Warn
                    else -> TagTone.Outline
                  },
          )
        }
        VText(
            text =
                "Off by default. When on, AI agents on your own Mac can read texts, contacts, " +
                    "call history and location from this phone, and ask before sending or calling.",
            style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
            color = colors.textDim,
        )
        VSwitch(
            checked = state.bridgeEnabled,
            onCheckedChange = state::updateBridgeEnabled,
            label = "Run Phone Bridge",
            enabled = state.bridgeAvailable,
        )
        state.bridgeNotificationSpec?.let { notif ->
          Row(
              modifier = Modifier.fillMaxWidth(),
              verticalAlignment = Alignment.CenterVertically,
              horizontalArrangement = Arrangement.spacedBy(Space.s3),
          ) {
            VText(
                text = notif.note,
                modifier = Modifier.weight(1f),
                style = VitruvianType.listSub,
                color = colors.warn,
            )
            VButton(
                label = notif.actionLabel,
                onClick = {
                  when (notif.action) {
                    Derive.NotificationPermissionAction.Allow ->
                        state.requestNotificationsPermission()
                    Derive.NotificationPermissionAction.OpenSettings ->
                        state.openNotificationSettings()
                    Derive.NotificationPermissionAction.None -> Unit
                  }
                },
            )
          }
        }
        VText(
            text = if (state.bridgeLinked) "Linked to the Mac helper" else state.bridgeLinkStatus,
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
        val problem = state.bridgeProblem
        state.bridgeProblemText?.let { text ->
          Row(
              modifier = Modifier.fillMaxWidth(),
              verticalAlignment = Alignment.CenterVertically,
              horizontalArrangement = Arrangement.spacedBy(Space.s3),
          ) {
            VText(
                text = text,
                modifier = Modifier.weight(1f),
                style = VitruvianType.listSub,
                color =
                    if (Derive.bridgeProblemIsBannerWorthy(problem)) colors.warn
                    else colors.textDim,
            )
            when (problem) {
              Derive.BridgeProblem.NotPaired -> VButton("Pair now", state::openPairing)
              Derive.BridgeProblem.Stopped -> VButton("Start", state::reconnectBridge)
              else -> VButton("Reconnect", state::reconnectBridge)
            }
          }
        }

        Rule(modifier = Modifier.fillMaxWidth().height(1.dp))

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
              subtitle = Derive.bridgePermissionSubtitle(permission.id, permission.granted),
              status = if (permission.granted) StatusTone.Ok else StatusTone.Warn,
              contentPadding = PaddingValues(vertical = Space.s3),
          ) {
            if (permission.granted) {
              Tag(text = "granted", tone = TagTone.Ok)
            } else if (permission.grantable) {
              VButton("Grant", { state.grantBridgePermission(permission.id) })
            } else {
              Tag(text = "in Settings", tone = TagTone.Outline)
            }
          }
        }

        Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
        Label("Recent calls · ${state.bridgeAudit.size} kept")
        if (state.bridgeAudit.isEmpty()) {
          VText(
              text = "No AI agent on your Mac has called a tool on this phone yet.",
              style = VitruvianType.listSub,
              color = colors.textDim,
          )
        }
        state.bridgeAudit.take(BRIDGE_AUDIT_SHOWN).forEach { entry ->
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
                tone = if (entry.outcome == "ok") TagTone.Ok else TagTone.Outline,
            )
          }
        }
      }
    }
  }
}
