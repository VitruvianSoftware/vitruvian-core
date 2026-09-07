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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.Metric
import dev.vitruvian.design.Plate
import dev.vitruvian.design.SegmentOption
import dev.vitruvian.design.Segmented
import dev.vitruvian.design.Space
import dev.vitruvian.design.Status
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.Terminal
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.overlays.DictateButton
import dev.vitruvian.remote.state.AppsView
import dev.vitruvian.remote.state.DialogKind
import dev.vitruvian.remote.state.MockHost
import dev.vitruvian.remote.state.ModuleDashboard
import dev.vitruvian.remote.state.ModuleMetric
import dev.vitruvian.remote.state.RemoteState

private val METRIC_MIN = 150.dp
private val STREAM_MAX_HEIGHT = 220.dp
private val INSTALL_BUTTON_MIN = 89.dp
private val CHIP_HEIGHT = 32.dp

/** Longer than this and a metric value is a name, not a number, and needs the smaller face. */
private const val METRIC_VALUE_MAX = 10

/**
 * Apps: installed module dashboards, and the gallery that installs them.
 *
 * A module is a manifest plus a data source plus a widget set; installing one adds a dashboard
 * here, widgets on Home and macros everywhere. The gallery is the whole extensibility story in one
 * list.
 */
@Composable
public fun ColumnScope.AppsScreen(state: RemoteState) {
  Box(modifier = Modifier.sectionPadding()) {
    Segmented(
        options =
            listOf(
                SegmentOption(
                    label = "Dashboards",
                    selected = state.appsView == AppsView.Dashboards,
                    onSelect = { state.showAppsView(AppsView.Dashboards) },
                ),
                SegmentOption(
                    label = "Gallery · ${MockHost.gallery.size}",
                    selected = state.appsView == AppsView.Gallery,
                    onSelect = { state.showAppsView(AppsView.Gallery) },
                ),
            ),
    )
  }
  when (state.appsView) {
    AppsView.Dashboards -> DashboardsPane(state)
    AppsView.Gallery -> GalleryPane(state)
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColumnScope.DashboardsPane(state: RemoteState) {
  val colors = Vitruvian
  val module = state.currentModule

  FlowRow(
      modifier = Modifier.padding(horizontal = Space.s4).fillMaxWidth(),
      horizontalArrangement = Arrangement.spacedBy(Space.s2),
      verticalArrangement = Arrangement.spacedBy(Space.s2),
  ) {
    state.moduleChips.forEach { entry ->
      Tag(
          text = entry.name,
          tone = if (state.module == entry.id) TagTone.Accent else TagTone.Outline,
          onClick = { state.selectModule(entry.id) },
          minHeight = CHIP_HEIGHT,
          contentPadding = PaddingValues(horizontal = Space.s4),
      )
    }
  }

  Row(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalAlignment = Alignment.Bottom,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.s1)) {
      VText(
          text = module.name,
          style = VitruvianType.h2,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis)
      VText(text = module.meta, style = VitruvianType.listSub, color = colors.textDim)
    }
    Status(tone = module.statusTone, text = module.status)
  }

  Box(modifier = Modifier.padding(horizontal = Space.s4)) {
    AutoGrid(minItemWidth = METRIC_MIN) {
      module.metrics.forEach { metric -> item { ModuleMetricPlate(metric) } }
    }
  }

  Box(modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s4)) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item { StreamPlate(state = state, module = module) }
      item { ModuleListPlate(module) }
    }
  }
}

/**
 * One metric plate on a module dashboard.
 *
 * The display face is 26 sp and a metric plate is 150 dp wide, so a value that is a metric NAME
 * rather than a number -- `mac_soc_power_watts` -- was arriving on screen as "mac_soc_powe". Long
 * values drop to the next size down and end in an ellipsis, which says "there is more" where a hard
 * clip says nothing at all.
 */
@Composable
private fun ModuleMetricPlate(metric: ModuleMetric) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    if (metric.value.length <= METRIC_VALUE_MAX) {
      Metric(
          label = metric.label,
          value = metric.value,
          delta = metric.sub,
          modifier = Modifier.padding(Space.s4),
      )
    } else {
      Column(
          modifier = Modifier.padding(Space.s4),
          verticalArrangement = Arrangement.spacedBy(Space.s2),
      ) {
        Label(metric.label)
        VText(
            text = metric.value,
            style = VitruvianType.barTitle,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        VText(
            text = metric.sub,
            style = VitruvianType.listSub,
            color = colors.textDim,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
      }
    }
  }
}

@Composable
private fun StreamPlate(state: RemoteState, module: ModuleDashboard) {
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Label(module.streamLabel)
      // A transcript nobody has written to is a lone cursor, which looks
      // like a stream that failed rather than one waiting for a first
      // prompt. Not a transcript line: nothing was said, so nothing is
      // quoted.
      if (module.prompts && module.lines.isEmpty()) {
        VText(
            text = "No prompts from this phone yet — type below.",
            style = VitruvianType.listSub,
            color = Vitruvian.textDim,
        )
      }
      Terminal(
          lines = module.lines,
          modifier =
              Modifier.heightIn(max = STREAM_MAX_HEIGHT).verticalScroll(rememberScrollState()),
          fontSize = 12.sp,
          cursor = module.cursor,
      )
      if (module.prompts) {
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
          VInput(
              value = state.prompt,
              onValueChange = state::updatePrompt,
              modifier = Modifier.weight(1f),
              placeholder = "Supplemental instruction…",
          )
          DictateButton(state) { spoken ->
            state.updatePrompt(
                listOf(state.prompt.trim(), spoken).filter { it.isNotBlank() }.joinToString(" "))
          }
          VButton("Send", state::sendModulePrompt, variant = ButtonVariant.Primary)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
          VButton(
              label = if (state.agentPaused) "Resume" else "Pause",
              onClick = state::toggleAgentPaused,
              modifier = Modifier.weight(1f),
          )
          VButton(
              label = "Halt",
              onClick = { state.openDialog(DialogKind.Halt) },
              modifier = Modifier.weight(1f),
              variant = ButtonVariant.Danger,
          )
        }
      }
    }
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ModuleListPlate(module: ModuleDashboard) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(modifier = Modifier.padding(Space.s4)) {
      Label(text = module.listLabel, modifier = Modifier.padding(bottom = Space.s3))
      module.rows.forEach { row ->
        ListItem(
            title = row.title,
            subtitle = row.subtitle,
            status = row.tone,
            onClick = row.onSelect,
            // The same accent rule the Hosts list uses for the selected Mac:
            // one selection idiom in the app, not two.
            selectedRule = if (row.selected) colors.accent else Color.Transparent,
            contentPadding = PaddingValues(vertical = Space.s3),
        ) {
          if (row.tag != null) {
            Tag(text = row.tag, tone = row.tagTone)
          }
          VText(
              text = row.trailing,
              style = VitruvianType.listSub,
              color = colors.textDim,
          )
        }
        // Under the row rather than inside it: four buttons in a 55 dp row's
        // trailing slot leaves the title two characters wide on a phone.
        if (row.actions.isNotEmpty()) {
          FlowRow(
              modifier = Modifier.fillMaxWidth().padding(bottom = Space.s3),
              horizontalArrangement = Arrangement.spacedBy(Space.s2),
              verticalArrangement = Arrangement.spacedBy(Space.s2),
          ) {
            row.actions.forEach { action ->
              VButton(
                  label = action.label,
                  onClick = action.onClick,
                  enabled = action.enabled,
                  variant = if (action.danger) ButtonVariant.Danger else ButtonVariant.Secondary,
              )
            }
          }
        }
      }
    }
  }
}

@Composable
private fun ColumnScope.GalleryPane(state: RemoteState) {
  val colors = Vitruvian
  VText(
      text =
          "Modules are signed bundles: a manifest, a data source " +
              "(SSH · HTTP · PromQL · MCP) and a widget set. Installed modules add a " +
              "dashboard, widgets and macros.",
      modifier = Modifier.padding(start = Space.s4, end = Space.s4, bottom = Space.s3),
      style = VitruvianType.listSub,
      color = colors.textDim,
  )
  MockHost.gallery.forEach { entry ->
    val installed = entry.id in state.installed
    // Live, the gallery reflects the Mac: a module whose program is not
    // there says so instead of offering an Install button for nothing.
    val why = state.moduleUnavailableReason(entry.id)
    ListItem(
        title = entry.name,
        subtitle = why ?: entry.subtitle,
        status =
            when {
              installed -> StatusTone.Ok
              why != null -> StatusTone.Warn
              else -> StatusTone.Neutral
            },
    ) {
      Tag(text = entry.source, tone = TagTone.Outline)
      VButton(
          label =
              when {
                installed -> "Remove"
                why != null -> "Not here"
                else -> "Install"
              },
          onClick = { state.toggleModule(entry.id) },
          modifier = Modifier.widthIn(min = INSTALL_BUTTON_MIN),
          variant = if (installed) ButtonVariant.Secondary else ButtonVariant.Primary,
          enabled = installed || why == null,
      )
    }
  }
  Box(modifier = Modifier.sectionPadding()) {
    Plate(modifier = Modifier.fillMaxWidth(), dashed = true) {
      Row(
          modifier = Modifier.padding(Space.s4).fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(Space.s4),
      ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(Space.s2),
        ) {
          Label("Sideload a module")
          VText(
              text = "Paste a manifest URL or a Grafana panel link.",
              style = VitruvianType.body.copy(fontSize = VitruvianType.mono.fontSize),
              color = colors.textDim,
          )
        }
        VButton("Add by URL", { state.sideload() })
      }
    }
  }
}
