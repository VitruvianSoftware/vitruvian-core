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

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
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
import dev.vitruvian.design.VIcon
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianIcons
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.AppInfo
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.MetricsSource
import dev.vitruvian.remote.state.RemoteState

private val PAIR_CODE_SIZE = 38.sp
private val PAIR_CODE_TRACKING = 0.18.em
private val REFRESH_INTERVALS = listOf("1 s", "5 s", "30 s")

/**
 * Settings: paired Macs, Phone Bridge entry, notifications, appearance, safety, macros and About.
 *
 * Reached from the host chip in every posture, and the first screen the app shows until a Mac is
 * paired.
 */
@Composable
public fun ColumnScope.HostsScreen(state: RemoteState) {
  val colors = Vitruvian

  // The permission answers change while this app is in the background -- the
  // user grants one from the system settings, or revokes it -- so they are
  // re-read every time the screen appears rather than once at construction.
  LaunchedEffect(Unit) {
    state.refreshBridgePermissions()
    state.refreshNotificationPermission()
  }

  Row(
      modifier =
          Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s5, bottom = Space.s3)
              .fillMaxWidth(),
      verticalAlignment = Alignment.Bottom,
  ) {
    Label(text = "Your Macs · ${state.hostRows.size}", modifier = Modifier.weight(1f))
    Status(tone = state.hostTone, text = state.connectionWord)
  }

  if (state.isUnpaired) {
    ListItem(
        title = "No Macs yet",
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
        placeholder = "Add a Mac · your Mac's address",
        imeAction = ImeAction.Go,
        onImeAction = state::addTypedHost,
    )
    VButton("Add", state::addTypedHost, enabled = state.newHostDraft.isNotBlank())
  }

  Box(modifier = Modifier.sectionPadding()) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item { AgentPlate(state) }
      item { PairPlate(state) }
    }
  }

  PhoneBridgeSection(state)
  NotificationsSection(state)
  AppearanceSection(state)
  SafetySection(state)

  Column(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s3).fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Macros")
    state.macros.forEach { macro ->
      val editable = state.userMacros.any { it.id == macro.id }
      ListItem(
          title = macro.label,
          subtitle = macro.command,
          status = StatusTone.Ok,
          onClick = if (editable) ({ state.editMacro(macro.id) }) else null,
          contentPadding = PaddingValues(vertical = Space.s3),
      ) {
        Tag(text = macro.kind.label, tone = TagTone.Outline)
        if (editable) {
          VText(text = "›", style = VitruvianType.listTitle, color = colors.textDim)
        }
      }
    }
    VButton(
        label = "+ New macro",
        onClick = state::openMacroEditor,
        modifier = Modifier.fillMaxWidth().padding(top = Space.s4),
        dashed = true,
    )
  }

  AboutSection(state)
}

@Composable
private fun PhoneBridgeSection(state: RemoteState) {
  val colors = Vitruvian
  val grantedCount = state.bridgePermissions.count { it.granted }
  val summary =
      Derive.phoneBridgeSummarySubtitle(
          enabled = state.bridgeEnabled,
          linked = state.bridgeLinked,
          linkStatus = state.bridgeLinkStatus,
          problemText = state.bridgeProblemText,
          grantedCount = grantedCount,
          totalCount = state.bridgePermissions.size,
      )
  val statusTone =
      when {
        state.bridgeLinked -> StatusTone.Ok
        Derive.bridgeProblemIsBannerWorthy(state.bridgeProblem) -> StatusTone.Warn
        else -> StatusTone.Neutral
      }
  Column(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s2).fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s2),
  ) {
    Label("Phone Bridge")
  }
  ListItem(
      title = "Phone Bridge",
      subtitle = summary,
      status = statusTone,
      onClick = state::openPhoneBridge,
      contentPadding = PaddingValues(horizontal = Space.s4, vertical = Space.s3),
  ) {
    VIcon(path = VitruvianIcons.CHEVRON_RIGHT, color = colors.textDim, contentDescription = null)
  }
}

@Composable
private fun NotificationsSection(state: RemoteState) {
  val colors = Vitruvian
  Column(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Notifications")
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4),
          verticalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        val notif = state.notificationsRowSpec
        ListItem(
            title = notif.title,
            subtitle = notif.subtitle,
            status =
                when {
                  notif.statusLabel != null -> StatusTone.Ok
                  notif.permanentlyBlocked -> StatusTone.Warn
                  else -> StatusTone.Neutral
                },
            contentPadding = PaddingValues(vertical = Space.s2),
        ) {
          when (notif.action) {
            Derive.NotificationPermissionAction.None ->
                notif.statusLabel?.let { Tag(text = it, tone = TagTone.Ok) }
            Derive.NotificationPermissionAction.Allow ->
                VButton(notif.actionLabel ?: "Allow", { state.requestNotificationsPermission() })
            Derive.NotificationPermissionAction.OpenSettings ->
                VButton(notif.actionLabel ?: "Open settings", state::openNotificationSettings)
          }
        }
        Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
        val push = state.pushNotifySpec
        VSwitch(
            checked = push.checked,
            onCheckedChange = state::setNotifications,
            label = "Mac push notifications",
            enabled = push.switchEnabled,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VText(
              text = push.subtitle,
              modifier = Modifier.weight(1f),
              style = VitruvianType.listSub,
              color = colors.textDim,
          )
          VButton("Test push", state::testPush, enabled = push.testEnabled)
        }
      }
    }
  }
}

@Composable
private fun AppearanceSection(state: RemoteState) {
  Column(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Appearance")
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4),
          verticalArrangement = Arrangement.spacedBy(Space.s4),
      ) {
        VSwitch(
            checked = !state.darkTheme,
            onCheckedChange = { state.toggleTheme() },
            label = "Light theme",
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
}

@Composable
private fun SafetySection(state: RemoteState) {
  Column(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Safety")
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4),
          verticalArrangement = Arrangement.spacedBy(Space.s4),
      ) {
        VSwitch(
            checked = state.confirmDestructive,
            onCheckedChange = state::updateConfirmDestructive,
            label = "Typed confirmation for restart / destroy",
        )
        VSwitch(
            checked = state.wakeOnLan,
            onCheckedChange = state::updateWakeOnLan,
            label = "Send Wake-on-LAN when your Mac stops answering",
        )
      }
    }
  }
}

@Composable
private fun AboutSection(state: RemoteState) {
  val colors = Vitruvian
  Column(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s3).fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s2),
  ) {
    Label("About")
  }
  ListItem(
      title = "About Vitruvian Remote",
      subtitle = "Version ${state.appVersion}",
      onClick = state::openAbout,
      contentPadding = PaddingValues(horizontal = Space.s4, vertical = Space.s3),
  ) {
    VIcon(path = VitruvianIcons.CHEVRON_RIGHT, color = colors.textDim, contentDescription = null)
  }
  ListItem(
      title = "Donate",
      subtitle = "Support development",
      onClick = { state.openExternalUrl(AppInfo.donateURL) },
      contentPadding = PaddingValues(horizontal = Space.s4, vertical = Space.s3),
  ) {
    VIcon(path = VitruvianIcons.EXTERNAL_LINK, color = colors.textDim, contentDescription = null)
  }
}

/**
 * The Mac helper: where it is, and whether it is answering.
 *
 * This is the only setting that changes what the dashboards show. The address is applied on
 * Connect, not per keystroke, and the status line says plainly which state the numbers are in.
 */
@Composable
private fun AgentPlate(state: RemoteState) {
  val colors = Vitruvian
  val status =
      when {
        state.isDemoMode -> "no Mac helper · dashboards are simulated"
        state.hostPhase == Derive.HostPhase.Unpaired -> "no Mac saved yet"
        // The tag beside this already says live / unreachable; repeating the
        // word made "LIVE live". The text carries what the tag cannot.
        state.metricsSource == MetricsSource.Live ->
            "${state.agentHost?.hostname ?: "host"} · helper v${state.agentHost?.agentVersion ?: "?"}"
        else -> state.agentError.ifBlank { "no answer yet" }
      }
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      // Says WHICH Mac is being edited. With more than one saved, a plate
      // headed "Mac helper" over a URL field is an invitation to retype the
      // wrong machine's address.
      Label("Mac helper · ${state.selectedHost?.alias?.ifBlank { null } ?: "none selected"}")
      VText(
          text =
              "Run the Mac helper on your Mac and enter your Mac's address. Edits the Mac above.",
          style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
          color = colors.textDim,
      )
      VInput(
          value = state.agentUrlDraft,
          onValueChange = state::updateAgentUrlDraft,
          modifier = Modifier.fillMaxWidth(),
          placeholder = "your Mac's address",
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
            onClick = state::requestForgetAgent,
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Danger,
            enabled = state.selectedHost != null,
        )
      }
      Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Tag(text = state.metricsTagLabel, tone = state.metricsTagTone)
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
// BringIntoViewRequester is still @ExperimentalFoundationApi in the Compose BOM
// pinned in MODULE.bazel (2024.11.00); it is the documented way to scroll a
// child of a verticalScroll into view.
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PairPlate(state: RemoteState) {
  val colors = Vitruvian
  // "Pair now" on the banner lands here, not at the top of the page.
  val requester = remember { BringIntoViewRequester() }
  LaunchedEffect(state.pairFocusRequest) {
    if (state.pairFocusRequest > 0) requester.bringIntoView()
  }
  Plate(modifier = Modifier.fillMaxWidth().bringIntoViewRequester(requester), marks = true) {
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
            // Amber while a configured Mac is refusing changes: that is a
            // problem, not merely a fact about a phone with no Mac yet.
            tone =
                when {
                  state.paired -> TagTone.Ok
                  state.needsPairing -> TagTone.Warn
                  else -> TagTone.Outline
                },
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
      // Why this plate matters right now: the Mac answers, and refuses changes.
      state.pairingBanner?.let { (_, body) ->
        VText(text = body, style = VitruvianType.listSub, color = colors.warn)
      }
      VText(
          text =
              "On your Mac, click Vitruvian Remote in the menu bar and choose Pair with QR Code, " +
                  "then scan it. Or enter this code there:",
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
