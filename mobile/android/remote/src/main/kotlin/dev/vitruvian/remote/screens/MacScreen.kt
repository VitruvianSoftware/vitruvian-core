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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.AutoGrid
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.Meter
import dev.vitruvian.design.Metric
import dev.vitruvian.design.Plate
import dev.vitruvian.design.SegBar
import dev.vitruvian.design.Space
import dev.vitruvian.design.Spark
import dev.vitruvian.design.Status
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.TableColumn
import dev.vitruvian.design.Tag
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VTable
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.HonestMetric
import dev.vitruvian.remote.state.MetricsSource
import dev.vitruvian.remote.state.RemoteState

private val PLATE_MIN = 150.dp
private val CPU_SPARK_HEIGHT = 44.dp
private val NET_SPARK_HEIGHT = 38.dp
private val PANEL_PREVIEW_HEIGHT = 96.dp

/** Above this a process reads as hot and its CPU cell turns warn-coloured. */
private const val PROCESS_WARN_CPU = 30

/**
 * Mac: the host dashboard.
 *
 * Everything here ticks; the numbers animate rather than jump because a jumping figure reads as a
 * glitch and an eased one reads as a measurement.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
public fun ColumnScope.MacScreen(state: RemoteState) {
  val colors = Vitruvian

  Row(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.s1)) {
      Label("Compute")
      VText(
          text = state.computeSubline,
          style = VitruvianType.listSub,
          color = colors.textDim,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
      )
    }
    // The source, not a decorative "live" - this said "live · 1s" while every
    // figure under it came from a random walk.
    Status(
        tone =
            when (state.metricsSource) {
              MetricsSource.Live -> StatusTone.Run
              MetricsSource.Unreachable -> StatusTone.Crit
              MetricsSource.Simulated -> StatusTone.Neutral
            },
        text = state.metricsSource.label,
    )
  }

  Box(modifier = Modifier.padding(horizontal = Space.s4)) {
    AutoGrid(minItemWidth = PLATE_MIN) {
      item(span = 2) {
        Plate(modifier = Modifier.fillMaxWidth()) {
          Column(
              modifier = Modifier.padding(Space.s4),
              verticalArrangement = Arrangement.spacedBy(Space.s3),
          ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom,
            ) {
              Label(text = "CPU", modifier = Modifier.weight(1f))
              VText(
                  text = "${state.cpu.last()}%",
                  style = VitruvianType.metricValue,
              )
            }
            Spark(values = state.cpu.toList(), height = CPU_SPARK_HEIGHT)
            Row(modifier = Modifier.fillMaxWidth()) {
              VText(
                  text = state.cpuBreakdown,
                  modifier = Modifier.weight(1f),
                  style = VitruvianType.label,
                  color = colors.textDim,
              )
              VText(text = "60 s", style = VitruvianType.label, color = colors.textDim)
            }
          }
        }
      }
      item { HonestPlate(state.gpuPlate) }
      item { HonestPlate(state.anePlate) }
    }
  }

  Column(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    val memory = state.memoryPlate
    Label(memory.label)
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
      VText(
          text = memory.value,
          modifier = Modifier.weight(1f),
          style = VitruvianType.metricValue,
      )
      VText(text = memory.sub, style = VitruvianType.listSub, color = colors.textDim)
    }
    SegBar(segments = state.memorySegments)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.s4)) {
      state.memoryBreakdown.forEach {
        VText(text = it, style = VitruvianType.label, color = colors.textDim)
      }
    }
  }

  Box(modifier = Modifier.padding(horizontal = Space.s4)) {
    AutoGrid(minItemWidth = PLATE_MIN) {
      item { HonestPlate(state.thermalPlate) }
      item { HonestPlate(state.batteryPlate) }
      item { HonestPlate(state.diskPlate) }
      item {
        Plate(modifier = Modifier.fillMaxWidth()) {
          Column(
              modifier = Modifier.padding(Space.s4),
              verticalArrangement = Arrangement.spacedBy(Space.s3),
          ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
              Label(text = "Network · en0", modifier = Modifier.weight(1f))
              VText(
                  text = "↓ ${state.networkDown} ↑ ${state.networkUp}",
                  style = VitruvianType.label,
                  color = colors.textDim,
              )
            }
            Spark(values = state.net.toList(), height = NET_SPARK_HEIGHT)
          }
        }
      }
    }
  }

  Label(text = "Top processes", modifier = Modifier.sectionPadding())
  val processNotice = state.processesNotice
  if (processNotice != null) {
    Unavailable(processNotice)
  } else {
    VTable(
        columns =
            listOf(
                TableColumn("Process"),
                TableColumn("CPU", alignEnd = true),
                TableColumn("Mem", alignEnd = true),
            ),
        rows =
            state.processes.map { process ->
              listOf(
                  process.name to null,
                  "${process.cpu}%" to if (process.cpu > PROCESS_WARN_CPU) colors.warn else null,
                  process.memory to null,
              )
            },
        modifier = Modifier.padding(horizontal = Space.s4),
        weights = listOf(2f, 1f, 1f),
    )
  }

  Label(text = "Lima VMs", modifier = Modifier.sectionPadding())
  val vmsNotice = state.vmsNotice
  if (vmsNotice != null) {
    Unavailable(vmsNotice)
  } else {
    state.vms.forEach { vm ->
      ListItem(title = vm.name, subtitle = vm.subtitle, status = vm.tone) {
        Tag(text = vm.tag, tone = vm.tagTone)
      }
    }
  }

  Label(text = state.containersLabel, modifier = Modifier.sectionPadding())
  val containersNotice = state.containersNotice
  if (containersNotice != null) {
    Unavailable(containersNotice)
  } else {
    state.containers.forEach { container ->
      ListItem(
          title = container.name,
          subtitle = container.subtitle,
          status = StatusTone.Ok,
      ) {
        VText(text = container.trailing, style = VitruvianType.listSub, color = colors.textDim)
      }
    }
  }

  Label(text = "K3s nodes", modifier = Modifier.sectionPadding())
  val nodesNotice = state.nodesNotice
  if (nodesNotice != null) {
    Unavailable(nodesNotice)
  } else {
    state.nodes.forEach { node ->
      ListItem(title = node.name, subtitle = node.subtitle, status = node.tone) {
        Tag(text = node.tag, tone = node.tagTone)
      }
    }
  }

  Column(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Custom panel · PromQL")
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4),
          verticalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
          VInput(
              value = state.promql,
              onValueChange = state::updatePromql,
              modifier = Modifier.weight(1f),
              textStyle = VitruvianType.mono,
          )
          VButton("Query", state::runPromql)
        }
        Plate(
            modifier = Modifier.fillMaxWidth().height(PANEL_PREVIEW_HEIGHT),
            dashed = true,
            gridField = true,
        ) {
          Label(
              text = state.promqlStatus,
              modifier =
                  Modifier.align(Alignment.Center)
                      .padding(horizontal = Space.s3, vertical = Space.s1),
          )
        }
        VText(
            text = state.promqlSource,
            style = VitruvianType.label,
            color = colors.textDim,
        )
      }
    }
  }
}

/**
 * A metric whose meter is optional.
 *
 * The nullable percent is the point. A bar drawn at zero says "this is idle"; there is no way to
 * draw "we cannot read this", so when there is no number the bar is simply absent and the sub-line
 * carries the reason.
 */
@Composable
private fun HonestPlate(metric: HonestMetric) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Metric(
          label = metric.label,
          value = metric.value,
          delta = metric.sub,
          valueColor = if (metric.warn) colors.warn else colors.text,
      )
      metric.percent?.let {
        Meter(
            fraction = it / 100f,
            fillColor = if (metric.warn) colors.warn else colors.accent,
        )
      }
    }
  }
}

/**
 * The reason a list is not here, in place of the list.
 *
 * Never an empty section: "no rows" and "the tool that produces the rows is not installed" look the
 * same on screen and mean opposite things.
 */
@Composable
private fun Unavailable(reason: String) {
  val colors = Vitruvian
  ListItem(title = reason, subtitle = "nothing measured", status = StatusTone.Neutral) {
    VText(text = "n/a", style = VitruvianType.listSub, color = colors.textDim)
  }
}
