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

package dev.vitruvian.wear.common

import kotlin.math.roundToInt

/**
 * Pure-JVM domain models and complication derivations for `vitruvian-pulse`.
 *
 * Kept free of Android and Compose imports so JVM unit tests verify every sub-dial range,
 * short-text formatting, and alert escalation rule without an emulator.
 */
public enum class PulseTone {
  Healthy,
  Warning,
  Critical,
  Idle,
}

public data class ComplicationGauge(
    val id: String,
    val title: String,
    val shortText: String,
    val longText: String,
    val value: Float,
    val min: Float = 0f,
    val max: Float = 100f,
    val tone: PulseTone = PulseTone.Healthy,
)

public data class HomelabSummary(
    val readyNodes: Int,
    val totalNodes: Int,
    val healthyPods: Int,
    val totalPods: Int,
    val firingAlerts: Int,
) {
  public fun deriveGauge(): ComplicationGauge {
    if (totalNodes <= 0 || totalPods <= 0) {
      return ComplicationGauge(
          id = "homelab",
          title = "K3S",
          shortText = "--",
          longText = "k3s cluster unreachable",
          value = 0f,
          tone = PulseTone.Idle,
      )
    }
    val nodeRatio = readyNodes.toFloat() / totalNodes.toFloat()
    val podRatio = healthyPods.toFloat() / totalPods.toFloat()
    val rawScore = ((nodeRatio * 0.4f + podRatio * 0.6f) * 100f).coerceIn(0f, 100f)
    val penalty = (firingAlerts * 15f).coerceAtMost(60f)
    val score = (rawScore - penalty).coerceIn(0f, 100f)

    val tone =
        when {
          readyNodes < totalNodes || firingAlerts >= 2 || score < 70f -> PulseTone.Critical
          firingAlerts == 1 || score < 95f -> PulseTone.Warning
          else -> PulseTone.Healthy
        }
    val shortText =
        if (firingAlerts > 0) {
          "${firingAlerts}!"
        } else {
          "${score.roundToInt()}%"
        }
    val longText =
        "Nodes $readyNodes/$totalNodes · Pods $healthyPods/$totalPods · Alerts $firingAlerts"
    return ComplicationGauge(
        id = "homelab",
        title = "K3S",
        shortText = shortText,
        longText = longText,
        value = score,
        tone = tone,
    )
  }
}

public data class MergeQueueSummary(
    val openPrs: Int,
    val queuedPrs: Int,
    val failingPrs: Int,
) {
  public fun deriveGauge(): ComplicationGauge {
    val cleanPrs = (openPrs - failingPrs).coerceAtLeast(0)
    val passRate =
        if (openPrs <= 0) {
          100f
        } else {
          ((cleanPrs.toFloat() / openPrs.toFloat()) * 100f).coerceIn(0f, 100f)
        }
    val tone =
        when {
          failingPrs > 0 -> PulseTone.Critical
          queuedPrs > 0 -> PulseTone.Warning
          openPrs > 0 -> PulseTone.Healthy
          else -> PulseTone.Idle
        }
    val shortText =
        when {
          failingPrs > 0 -> "${failingPrs}✗"
          queuedPrs > 0 -> "${queuedPrs}Q"
          else -> "$openPrs"
        }
    val longText = "PRs: $openPrs open · $queuedPrs queued · $failingPrs red"
    return ComplicationGauge(
        id = "prs",
        title = "PRs",
        shortText = shortText,
        longText = longText,
        value = passRate,
        tone = tone,
    )
  }
}

public data class RoborockSummary(
    val state: String,
    val batteryPercent: Int,
    val roomName: String = "",
    val cleanAreaSqm: Int = 0,
) {
  public fun deriveGauge(): ComplicationGauge {
    val clampedBattery = batteryPercent.coerceIn(0, 100)
    val normalized = state.trim().lowercase()
    val tone =
        when {
          "error" in normalized || "stuck" in normalized || clampedBattery < 15 ->
              PulseTone.Critical
          "clean" in normalized || "wash" in normalized || "return" in normalized ->
              PulseTone.Warning
          clampedBattery >= 80 -> PulseTone.Healthy
          else -> PulseTone.Idle
        }
    val shortText =
        when {
          "clean" in normalized -> "CLN"
          "wash" in normalized -> "MOP"
          "error" in normalized -> "ERR"
          else -> "$clampedBattery%"
        }
    val roomSuffix = if (roomName.isNotBlank()) " ($roomName)" else ""
    val areaSuffix = if (cleanAreaSqm > 0) " · ${cleanAreaSqm}m²" else ""
    val longText =
        "${state.replaceFirstChar { it.uppercase() }}$roomSuffix · $clampedBattery%$areaSuffix"
    return ComplicationGauge(
        id = "roborock",
        title = "VAC",
        shortText = shortText,
        longText = longText,
        value = clampedBattery.toFloat(),
        tone = tone,
    )
  }
}
