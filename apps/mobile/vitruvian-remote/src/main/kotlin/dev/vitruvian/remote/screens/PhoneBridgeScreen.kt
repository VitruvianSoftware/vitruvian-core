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
import dev.vitruvian.design.VDialog
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.AppInfo
import dev.vitruvian.remote.state.BridgePolicy
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.Format
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.TrustDuration
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
  var confirmAlwaysTrust by remember { mutableStateOf(false) }

  LaunchedEffect(Unit) {
    state.refreshBridgePermissions()
    state.refreshNotificationPermission()
    state.refreshPhoneVoices()
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
            text = AppInfo.phoneBridgeScreenSummary,
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
                color = if (state.trustAlways) colors.warn else colors.text,
            )
            VButton("End trust", state::endTrust)
          }
        } else {
          Label("Trust agents")
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Space.s2),
        ) {
          TrustDuration.entries.forEach { duration ->
            val selectedAlways = duration == TrustDuration.Always && state.trustAlways
            VButton(
                label = duration.label,
                onClick = {
                  if (duration == TrustDuration.Always) {
                    confirmAlwaysTrust = true
                  } else {
                    state.trustAgents(duration)
                  }
                },
                modifier = Modifier.weight(1f),
                variant = if (selectedAlways) ButtonVariant.Primary else ButtonVariant.Secondary,
                enabled = state.bridgeAvailable && !selectedAlways,
                contentPadding = PaddingValues(horizontal = Space.s3),
            )
          }
        }
        when {
          state.trustAlways ->
              VText(
                  text =
                      "Permanent trust stays on until you tap End trust. Screen control, apps, " +
                          "texts and calls run without asking.",
                  style = VitruvianType.listSub,
                  color = colors.textDim,
              )
          !state.trustOpen ->
              VText(
                  text =
                      "Off, screen control and opening apps are refused and texts and calls ask " +
                          "here first.",
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

        if (state.phoneVoicesAvailable) {
          Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
          AnnouncementVoicePicker(state)
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
              statusAdjacentText = entry.outcome,
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

  if (confirmAlwaysTrust) {
    VDialog(
        onDismissRequest = { confirmAlwaysTrust = false },
        kicker = "Trust agents",
        kickerColor = colors.warn,
        title = "Trust agents always?",
        body =
            "AI agents on your paired Mac will be able to control the screen, open apps, " +
                "send texts, place calls and reply to notifications without asking until you tap " +
                "End trust.",
    ) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(Space.s3, Alignment.End),
      ) {
        VButton("Cancel", { confirmAlwaysTrust = false })
        VButton(
            label = "Trust always",
            onClick = {
              confirmAlwaysTrust = false
              state.trustAgents(TrustDuration.Always)
            },
            variant = ButtonVariant.Primary,
        )
      }
    }
  }
}

/**
 * The voice the phone speaks Vitruvian Speaker announcements with, when the Mac sends text rather
 * than Gemini audio. Google's on-device voices only; the plain Android voice stays the fallback.
 */
@Composable
private fun AnnouncementVoicePicker(state: RemoteState) {
  val colors = Vitruvian
  val inUse = state.phoneVoiceInUse
  Row(
      modifier = Modifier.fillMaxWidth(),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label(text = "Announcement voice", modifier = Modifier.weight(1f))
    VButton("Refresh", state::refreshPhoneVoices, enabled = !state.phoneVoicesLoading)
  }
  VText(
      text =
          "Google's on-device voices, free and offline. Used when the Mac sends text; if none is on " +
              "this phone, the standard Android voice speaks instead.",
      style = VitruvianType.listSub,
      color = colors.textDim,
  )
  when {
    state.phoneVoicesLoading && state.phoneVoiceOptions.isEmpty() ->
        VText(text = "Looking for voices…", style = VitruvianType.listSub, color = colors.textDim)
    state.phoneVoiceOptions.isEmpty() ->
        VText(
            text =
                "No on-device voices on this phone. Update Speech Recognition & Synthesis from " +
                    "Google Play to get them.",
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
    else -> {
      ListItem(
          title = "Automatic",
          subtitle = "The first voice already on this phone",
          status = if (state.phoneVoice.isEmpty()) StatusTone.Ok else null,
          contentPadding = PaddingValues(vertical = Space.s3),
      ) {
        if (state.phoneVoice.isEmpty()) {
          Tag(text = "selected", tone = TagTone.Ok)
        } else {
          VButton("Use", { state.selectPhoneVoice("") })
        }
      }
      val showLanguage = BridgePolicy.voicesMixLanguages(state.phoneVoiceOptions)
      state.phoneVoiceOptions.forEach { voice ->
        val picked = state.phoneVoice == voice.name
        val ready = voice.status == BridgePolicy.MlKitVoiceStatus.Available
        ListItem(
            title = BridgePolicy.voiceTitle(voice.name),
            subtitle = BridgePolicy.voiceSubtitle(voice, showLanguage),
            status =
                when {
                  voice.name == inUse && picked -> StatusTone.Ok
                  picked -> StatusTone.Warn
                  else -> null
                },
            contentPadding = PaddingValues(vertical = Space.s3),
        ) {
          Row(horizontalArrangement = Arrangement.spacedBy(Space.s2)) {
            if (ready) {
              VButton(
                  label = if (state.phoneVoicePreviewing == voice.name) "Playing…" else "Play",
                  onClick = { state.previewPhoneVoice(voice.name) },
                  enabled = state.phoneVoicePreviewing == null,
              )
            }
            when {
              picked -> Tag(text = "selected", tone = if (ready) TagTone.Ok else TagTone.Warn)
              voice.status == BridgePolicy.MlKitVoiceStatus.Unavailable -> Unit
              else ->
                  VButton(
                      label = if (ready) "Use" else "Get",
                      onClick = { state.selectPhoneVoice(voice.name) },
                  )
            }
          }
        }
      }
      if (state.phoneVoice.isNotEmpty() && inUse != null && inUse != state.phoneVoice) {
        VText(
            text =
                "Until your pick is on this phone, announcements use ${BridgePolicy.voiceTitle(inUse)}.",
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
      }
    }
  }
  state.phoneVoiceNote?.let {
    VText(text = it, style = VitruvianType.listSub, color = colors.textDim)
  }
}
