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

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.BlinkingCursor
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Hit
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
import dev.vitruvian.design.TerminalLine
import dev.vitruvian.design.TerminalTone
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.design.bottomHairline
import dev.vitruvian.remote.overlays.DictateButton
import dev.vitruvian.remote.state.AppsView
import dev.vitruvian.remote.state.Derive
import dev.vitruvian.remote.state.DialogKind
import dev.vitruvian.remote.state.Markdown
import dev.vitruvian.remote.state.MockHost
import dev.vitruvian.remote.state.ModuleDashboard
import dev.vitruvian.remote.state.ModuleMetric
import dev.vitruvian.remote.state.ModuleRow
import dev.vitruvian.remote.state.PendingPermission
import dev.vitruvian.remote.state.RemoteState
import kotlinx.coroutines.delay

private val METRIC_MIN = 150.dp
private val STREAM_MAX_HEIGHT = 220.dp
private val INSTALL_BUTTON_MIN = 89.dp
private val CHIP_HEIGHT = 32.dp
private val STREAM_FONT = 12.sp
private val SELECTED_RULE = 2.dp

/** A prompt's summary is one command or path; three lines is enough to recognise it. */
private const val SUMMARY_MAX_LINES = 3

/** The countdowns move a second at a time, so the clock does too. */
private const val COUNTDOWN_TICK_MS = 1000L

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

  // One row that scrolls sideways. Nine chips wrapped to three rows and
  // took a third of a folded screen before the dashboard started.
  val chips = state.moduleChips
  val chipRow = rememberLazyListState()
  // Keep the selection on screen, including when it was chosen elsewhere --
  // a tap on Home's "Running now" lands here with a chip possibly off the end.
  LaunchedEffect(state.module, chips.size) {
    val index = chips.indexOfFirst { it.id == state.module }
    if (index >= 0) chipRow.animateScrollToItem(index)
  }
  LazyRow(
      state = chipRow,
      modifier = Modifier.fillMaxWidth(),
      contentPadding = PaddingValues(horizontal = Space.s4),
      horizontalArrangement = Arrangement.spacedBy(Space.s2),
  ) {
    items(chips, key = { it.id }) { entry ->
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

  // Above the transcript: a prompt waiting here is the most urgent thing on
  // this dashboard, and a Claude session stays blocked until it is answered.
  if (module.id == "claude") {
    Box(modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s4)) {
      ClaudePromptsPlate(state)
    }
  }

  Box(modifier = Modifier.padding(start = Space.s4, end = Space.s4, top = Space.s4)) {
    AutoGrid(minItemWidth = TWO_UP_MIN, gap = Space.s4) {
      item { StreamPlate(state = state, module = module) }
      item { ModuleListPlate(module.listLabel, module.rows) }
      module.extraLists.forEach { list -> item { ModuleListPlate(list.label, list.rows) } }
    }
  }
}

/**
 * One metric plate on a module dashboard.
 *
 * The display face is 26 sp and a metric plate is 150 dp wide, so a value that is a metric NAME
 * rather than a number -- `mac_soc_power_watts` -- was arriving on screen as "mac_soc_powe". Long
 * values drop to the next size down, and wrap to a second line before they ellipsise: a name is
 * words, and "Lake Office display" cut to "Lake Office disp…" reads as a different speaker from the
 * one the Mac is actually using. The ellipsis stays for the third line, where it says "there is
 * more" rather than clipping silently.
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
            maxLines = 2,
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

/**
 * Claude Code's permission prompts, answered from the phone (API v1.6).
 *
 * The toggle installs a hook in Claude Code on the Mac, so it shows the Mac's state rather than the
 * tap, and says what it is doing while the Mac does it. Anything that stops it working -- no
 * pairing, an older agent, a Mac not answering -- replaces the controls with one line saying which,
 * because a switch that silently does nothing is worse than no switch.
 */
@Composable
private fun ClaudePromptsPlate(state: RemoteState) {
  val colors = Vitruvian
  // One clock for every countdown on the plate, so the cards tick together.
  var now by remember { mutableStateOf(System.currentTimeMillis()) }
  LaunchedEffect(Unit) {
    while (true) {
      now = System.currentTimeMillis()
      delay(COUNTDOWN_TICK_MS)
    }
  }
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Label("Permission prompts")
      val notice = state.claudeApprovalsNotice
      if (notice != null) {
        VText(text = notice, style = VitruvianType.listSub, color = colors.textDim)
        return@Column
      }
      val pending = state.claudeEnabledPending
      VSwitch(
          checked = state.claudeEnabled,
          onCheckedChange = state::setClaudePermissionsEnabled,
          label = "Answer Claude prompts on this phone",
          enabled = pending == null,
      )
      VText(
          text =
              if (pending != null) Derive.claudeHookBusyLabel(pending)
              else
                  Derive.claudeHookExplanation(
                      state.claudeEnabled, state.hostShortName, state.claudeWaitSeconds),
          style = VitruvianType.listSub,
          color = colors.textDim,
      )
      // The Mac's own words, e.g. that settings.json is not valid JSON.
      if (state.claudeEnabledError.isNotBlank()) {
        VText(
            text = state.claudeEnabledError,
            style = VitruvianType.listSub,
            color = colors.sanguineText,
        )
      }
      if (!state.claudeEnabled) return@Column
      if (state.claudeApprovalsError.isNotBlank()) {
        VText(
            text = "Could not refresh: ${state.claudeApprovalsError}",
            style = VitruvianType.listSub,
            color = colors.warn,
        )
      }
      if (state.claudePending.isEmpty()) {
        VText(text = "Nothing waiting.", style = VitruvianType.listSub, color = colors.textDim)
      }
      state.claudePending.forEach { item -> PendingPromptCard(state, item, now) }
    }
  }
}

/** One prompt: what Claude wants to do, where, how long is left, and the two answers. */
@Composable
private fun PendingPromptCard(state: RemoteState, item: PendingPermission, now: Long) {
  val colors = Vitruvian
  var expanded by remember(item.id) { mutableStateOf(false) }
  // An unreadable deadline shows no countdown rather than "expired": the
  // agent may well still be holding it, and it answers 404 if not.
  val left = if (item.expiresAtMs > 0) Derive.timeLeft(item.expiresAtMs, now) else null
  val expired = left == "expired"
  Column(
      modifier = Modifier.fillMaxWidth().bottomHairline(colors.line).padding(bottom = Space.s3),
      verticalArrangement = Arrangement.spacedBy(Space.s2),
  ) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Status(tone = if (expired) StatusTone.Neutral else StatusTone.Warn)
      VText(
          text = listOf(item.tool, item.project).filter { it.isNotBlank() }.joinToString(" · "),
          style = VitruvianType.listTitle,
          modifier = Modifier.weight(1f),
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
      )
      if (left != null) Tag(text = left, tone = if (expired) TagTone.Neutral else TagTone.Warn)
    }
    if (item.summary.isNotBlank()) {
      VText(
          text = item.summary,
          style = VitruvianType.mono,
          maxLines = SUMMARY_MAX_LINES,
          overflow = TextOverflow.Ellipsis,
      )
    }
    if (item.detail.isNotBlank() && item.detail != item.summary) {
      VButton(
          label = if (expanded) "Hide details" else "Show details",
          onClick = { expanded = !expanded },
          variant = ButtonVariant.Ghost,
          contentPadding = PaddingValues(horizontal = Space.s1),
      )
      if (expanded) {
        VText(
            text = item.detail,
            style = VitruvianType.mono,
            color = colors.textDim,
            modifier =
                Modifier.fillMaxWidth()
                    .heightIn(max = STREAM_MAX_HEIGHT)
                    .verticalScroll(rememberScrollState()),
        )
      }
    }
    if (state.claudeDenyingId == item.id) {
      // Optional: an empty reason still denies, and the Mac's hook fills in
      // "Denied from the phone".
      VInput(
          value = state.claudeDenyReason,
          onValueChange = state::updateClaudeDenyReason,
          modifier = Modifier.fillMaxWidth(),
          placeholder = "Reason for Claude (optional)",
          imeAction = ImeAction.Send,
          onImeAction = { state.denyClaude(item.id, state.claudeDenyReason) },
      )
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton(
            label = "Cancel",
            onClick = state::cancelDenyClaude,
            modifier = Modifier.weight(1f),
        )
        VButton(
            label = "Send deny",
            onClick = { state.denyClaude(item.id, state.claudeDenyReason) },
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Danger,
            enabled = !expired,
        )
      }
    } else {
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton(
            label = "Deny",
            onClick = { state.startDenyClaude(item.id) },
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Danger,
            enabled = !expired,
        )
        VButton(
            label = "Approve",
            onClick = { state.approveClaude(item.id) },
            modifier = Modifier.weight(1f),
            variant = ButtonVariant.Primary,
            enabled = !expired,
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
      // Markdown streams are the two agents' transcripts: Claude's and Antigravity's.
      if ((module.prompts || module.markdown) && module.lines.isEmpty()) {
        VText(
            text = "No prompts from this phone yet — type below.",
            style = VitruvianType.listSub,
            color = Vitruvian.textDim,
        )
      }
      // Follow the newest line. The box is capped in height, and without
      // this a reply streamed in below the fold: on the Fold the answer to a
      // second prompt was invisible under the first one's output, and the
      // page scrolled instead of the box. Scrolling to the end whenever the
      // line count changes keeps the latest exchange in view.
      val streamScroll = rememberScrollState()
      LaunchedEffect(module.lines.size) { streamScroll.animateScrollTo(streamScroll.maxValue) }
      val streamModifier = Modifier.heightIn(max = STREAM_MAX_HEIGHT).verticalScroll(streamScroll)
      if (module.markdown) {
        MarkdownStream(lines = module.lines, modifier = streamModifier, cursor = module.cursor)
      } else {
        Terminal(
            lines = module.lines,
            modifier = streamModifier,
            fontSize = STREAM_FONT,
            cursor = module.cursor,
        )
      }
      module.composer?.let { composer ->
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
          VInput(
              value = composer.value,
              onValueChange = composer.onValueChange,
              modifier = Modifier.weight(1f),
              placeholder = composer.placeholder,
          )
          DictateButton(state) { spoken ->
            composer.onValueChange(
                listOf(composer.value.trim(), spoken).filter { it.isNotBlank() }.joinToString(" "))
          }
          VButton(
              composer.buttonLabel,
              composer.onSubmit,
              enabled = composer.enabled,
              variant = ButtonVariant.Primary)
        }
      }
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
private fun ModuleListPlate(label: String, rows: List<ModuleRow>) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(modifier = Modifier.padding(Space.s4)) {
      Label(text = label, modifier = Modifier.padding(bottom = Space.s3))
      rows.forEach { row ->
        val trailing: @Composable RowScope.() -> Unit = {
          if (row.tag != null) {
            Tag(text = row.tag, tone = row.tagTone)
          }
          VText(
              text = row.trailing,
              style = VitruvianType.listSub,
              color = colors.textDim,
          )
        }
        if (row.titleLines > 1) {
          WrappingRow(row, trailing)
        } else {
          ListItem(
              title = row.title,
              subtitle = row.subtitle,
              status = row.tone,
              onClick = row.onSelect,
              // The same accent rule the Hosts list uses for the selected Mac:
              // one selection idiom in the app, not two.
              selectedRule = if (row.selected) colors.accent else Color.Transparent,
              contentPadding = PaddingValues(vertical = Space.s3),
              trailing = trailing,
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
      // What is true: there are no bundles and no SSH. Every module is a view
      // of something the agent already reads, tagged with the tool it runs.
      text =
          "Each module is a view of something the Mac agent can see. " +
              "Remove one to hide its dashboard.",
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

/**
 * A module row whose title may wrap.
 *
 * `ListItem` is one line of title by design, which is right for a session or a container and wrong
 * for a pull request: its title is the content, and on a folded phone one line of
 * "VitruvianSoftware/vitruvian-core#25…" was all there was. Built from the same parts -- the 55 dp
 * floor, the hairline, the status dot, the selected rule -- so it reads as the same list.
 */
@Composable
private fun WrappingRow(row: ModuleRow, trailing: @Composable RowScope.() -> Unit) {
  val colors = Vitruvian
  Row(
      modifier =
          Modifier.fillMaxWidth()
              .defaultMinSize(minHeight = Hit.h2)
              .bottomHairline(colors.line)
              .then(
                  row.onSelect?.let { Modifier.clickable(onClick = it) } ?: Modifier,
              )
              .padding(vertical = Space.s3),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    if (row.selected) {
      Box(
          modifier =
              Modifier.width(SELECTED_RULE)
                  .fillMaxHeight()
                  .defaultMinSize(minHeight = Hit.h2)
                  .background(colors.accent),
      )
    }
    Status(tone = row.tone)
    Column(modifier = Modifier.weight(1f)) {
      VText(
          text = row.title,
          style = VitruvianType.listTitle,
          maxLines = row.titleLines,
          overflow = TextOverflow.Ellipsis,
      )
      VText(
          text = row.subtitle,
          style = VitruvianType.listSub,
          color = colors.textDim,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
      )
    }
    trailing()
  }
}

/**
 * The Claude Code transcript, with its Markdown drawn rather than printed.
 *
 * The same ground, prefix column and colours as `Terminal`, which takes plain strings and so showed
 * `**Gist**` and `- ` bullets literally. [Markdown] does the parsing (and is tested on the JVM);
 * this only turns its blocks into styled text. Each paragraph or bullet is its own row, with the
 * line's prefix on the first and blank space under it on the rest, so the prefix column stays a
 * column.
 */
@Composable
private fun MarkdownStream(lines: List<TerminalLine>, modifier: Modifier, cursor: Boolean) {
  val colors = Vitruvian
  val style = VitruvianType.terminal.copy(fontSize = STREAM_FONT)
  val code = SpanStyle(color = colors.accentText)
  Column(
      modifier =
          modifier
              .fillMaxWidth()
              .background(colors.neutral900)
              .border(1.dp, colors.divider)
              .padding(horizontal = Space.s4, vertical = Space.s3),
      verticalArrangement = Arrangement.spacedBy(Space.s1),
  ) {
    val roles = Markdown.lineRoles(lines.map { it.text })
    lines.forEachIndexed { lineIndex, line ->
      val role = roles[lineIndex]
      if (role == Markdown.LineRole.Fence) return@forEachIndexed
      val blocks =
          when (role) {
            Markdown.LineRole.Heading ->
                listOf(
                    Markdown.Block(
                        Markdown.Kind.Paragraph,
                        listOf(Markdown.Span(Markdown.headingText(line.text), bold = true)),
                    ))
            Markdown.LineRole.Code ->
                listOf(
                    Markdown.Block(
                        Markdown.Kind.Paragraph, listOf(Markdown.Span(line.text, code = true))))
            else -> Markdown.parse(line.text)
          }
      val color =
          when (line.tone) {
            TerminalTone.Text -> colors.text
            TerminalTone.Dim -> colors.textDim
            TerminalTone.Ok -> colors.ok
            TerminalTone.Warn -> colors.warn
            TerminalTone.Err -> colors.sanguineText
          }
      val rows = blocks.ifEmpty { listOf(Markdown.Block(Markdown.Kind.Paragraph, emptyList())) }
      rows.forEachIndexed { index, block ->
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
          VText(
              // Mono, so spaces of the prefix's length hold the column.
              text = if (index == 0) line.prefix else " ".repeat(line.prefix.length),
              style = style,
              color = colors.accent400,
              softWrap = false,
          )
          VText(text = styled(block, code), style = style, color = color)
        }
      }
    }
    if (cursor) BlinkingCursor()
  }
}

private fun styled(block: Markdown.Block, code: SpanStyle): AnnotatedString = buildAnnotatedString {
  if (block.kind == Markdown.Kind.Bullet) append("• ")
  block.spans.forEach { span ->
    val bold = if (span.bold) SpanStyle(fontWeight = FontWeight.Bold) else null
    when {
      span.code && bold != null -> withStyle(bold.merge(code)) { append(span.text) }
      span.code -> withStyle(code) { append(span.text) }
      bold != null -> withStyle(bold) { append(span.text) }
      else -> append(span.text)
    }
  }
}
