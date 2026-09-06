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
import dev.vitruvian.remote.state.BATTERY_PERCENT
import dev.vitruvian.remote.state.DISK_PERCENT
import dev.vitruvian.remote.state.MEMORY_PERCENT
import dev.vitruvian.remote.state.MockHost
import dev.vitruvian.remote.state.RemoteState
import dev.vitruvian.remote.state.THERMAL_WARN_C

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
          text = "Apple M4 Max · 16c CPU · 40c GPU · 64 GB",
          style = VitruvianType.listSub,
          color = colors.textDim,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
      )
    }
    Status(tone = StatusTone.Run, text = "live · 1s")
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
                  text = "P-cores 34% · E-cores 12%",
                  modifier = Modifier.weight(1f),
                  style = VitruvianType.label,
                  color = colors.textDim,
              )
              VText(text = "60 s", style = VitruvianType.label, color = colors.textDim)
            }
          }
        }
      }
      item { MeterPlate("GPU", "${state.gpu}%", state.gpu, "Metal · 2 clients") }
      item { MeterPlate("Neural Engine", "${state.ane}%", state.ane, "ollama · llama3.3") }
    }
  }

  Column(
      modifier = Modifier.sectionPadding().fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Memory pressure")
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
      VText(
          text = "$MEMORY_PERCENT%",
          modifier = Modifier.weight(1f),
          style = VitruvianType.metricValue,
      )
      VText(
          text = "26.4 / 64 GB · swap 0 B",
          style = VitruvianType.listSub,
          color = colors.textDim,
      )
    }
    SegBar(segments = state.memorySegments)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.s4)) {
      listOf("app 18.1 GB", "wired 4.2 GB", "compressed 2.1 GB", "cached 12 GB").forEach {
        VText(text = it, style = VitruvianType.label, color = colors.textDim)
      }
    }
  }

  Box(modifier = Modifier.padding(horizontal = Space.s4)) {
    AutoGrid(minItemWidth = PLATE_MIN) {
      item {
        Plate(modifier = Modifier.fillMaxWidth()) {
          Column(
              modifier = Modifier.padding(Space.s4),
              verticalArrangement = Arrangement.spacedBy(Space.s3),
          ) {
            val hot = state.temperature > THERMAL_WARN_C
            Metric(
                label = "Thermals",
                value = "${state.temperature}°",
                delta = "fans ${state.fanRpm} rpm",
                valueColor = if (hot) colors.warn else colors.text,
            )
            Meter(
                fraction = state.temperature / 100f,
                fillColor = if (hot) colors.warn else colors.accent,
            )
          }
        }
      }
      item {
        MeterPlate(
            label = "Battery",
            value = "$BATTERY_PERCENT%",
            percent = BATTERY_PERCENT,
            delta = "${state.powerDraw} W · on AC",
        )
      }
      item {
        MeterPlate(
            label = "Disk · Macintosh HD",
            value = "1.21 / 2 TB",
            percent = DISK_PERCENT,
            delta = "R 42 MB/s · W 8 MB/s",
        )
      }
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
  VTable(
      columns =
          listOf(
              TableColumn("Process"),
              TableColumn("CPU", alignEnd = true),
              TableColumn("Mem", alignEnd = true),
          ),
      rows =
          MockHost.processes.map { process ->
            listOf(
                process.name to null,
                "${process.cpu}%" to if (process.cpu > PROCESS_WARN_CPU) colors.warn else null,
                process.memory to null,
            )
          },
      modifier = Modifier.padding(horizontal = Space.s4),
      weights = listOf(2f, 1f, 1f),
  )

  Label(text = "Lima VMs · K3s nodes", modifier = Modifier.sectionPadding())
  MockHost.vms.forEach { vm ->
    ListItem(title = vm.name, subtitle = vm.subtitle, status = vm.tone) {
      Tag(text = vm.tag, tone = vm.tagTone)
    }
  }

  Label(text = "Docker · 5 containers", modifier = Modifier.sectionPadding())
  MockHost.containers.forEach { container ->
    ListItem(
        title = container.name,
        subtitle = container.subtitle,
        status = StatusTone.Ok,
    ) {
      VText(text = container.cpu, style = VitruvianType.listSub, color = colors.textDim)
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
              onValueChange = state::setPromql,
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
            text = "source · grafana.homelab.local · prometheus",
            style = VitruvianType.label,
            color = colors.textDim,
        )
      }
    }
  }
}

/**
 * A metric over a meter.
 *
 * [delta] sits under the value, inside the metric stack; [caption] sits under the bar. The two are
 * different rows in the CSS and different information - a delta qualifies the number, a caption
 * names its source.
 */
@Composable
private fun MeterPlate(
    label: String,
    value: String,
    percent: Int,
    caption: String? = null,
    delta: String? = null,
) {
  val colors = Vitruvian
  Plate(modifier = Modifier.fillMaxWidth()) {
    Column(
        modifier = Modifier.padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Metric(label = label, value = value, delta = delta)
      Meter(fraction = percent / 100f)
      if (caption != null) {
        VText(text = caption, style = VitruvianType.label, color = colors.textDim)
      }
    }
  }
}
