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

package dev.vitruvian.wear.pulse

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import dev.vitruvian.wear.common.ComplicationGauge
import dev.vitruvian.wear.common.HomelabSummary
import dev.vitruvian.wear.common.MergeQueueSummary
import dev.vitruvian.wear.common.RoborockSummary

/**
 * Shared state repository and Wear OS complication binder services for `vitruvian-pulse`.
 *
 * Exposes 3 complication data source services (`HomelabPulseComplicationService`,
 * `MergeQueueComplicationService`, `RoborockPulseComplicationService`) that bind to the Daytona
 * Platinum watch face sub-dials (`RANGED_VALUE`, `SHORT_TEXT`, `LONG_TEXT`).
 */
public object PulseRepository {
  private const val PREFS_NAME = "vitruvian_pulse_state"

  public fun readHomelab(context: Context): HomelabSummary {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    return HomelabSummary(
        readyNodes = prefs.getInt("homelab_ready_nodes", 3),
        totalNodes = prefs.getInt("homelab_total_nodes", 3),
        healthyPods = prefs.getInt("homelab_healthy_pods", 96),
        totalPods = prefs.getInt("homelab_total_pods", 96),
        firingAlerts = prefs.getInt("homelab_firing_alerts", 0),
    )
  }

  public fun writeHomelab(context: Context, summary: HomelabSummary) {
    context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putInt("homelab_ready_nodes", summary.readyNodes)
        .putInt("homelab_total_nodes", summary.totalNodes)
        .putInt("homelab_healthy_pods", summary.healthyPods)
        .putInt("homelab_total_pods", summary.totalPods)
        .putInt("homelab_firing_alerts", summary.firingAlerts)
        .apply()
  }

  public fun readMergeQueue(context: Context): MergeQueueSummary {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    return MergeQueueSummary(
        openPrs = prefs.getInt("pr_open", 7),
        queuedPrs = prefs.getInt("pr_queued", 1),
        failingPrs = prefs.getInt("pr_failing", 0),
    )
  }

  public fun writeMergeQueue(context: Context, summary: MergeQueueSummary) {
    context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putInt("pr_open", summary.openPrs)
        .putInt("pr_queued", summary.queuedPrs)
        .putInt("pr_failing", summary.failingPrs)
        .apply()
  }

  public fun readRoborock(context: Context): RoborockSummary {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    return RoborockSummary(
        state = prefs.getString("roborock_state", "Docked") ?: "Docked",
        batteryPercent = prefs.getInt("roborock_battery", 100),
        roomName = prefs.getString("roborock_room", "Lake Office") ?: "Lake Office",
        cleanAreaSqm = prefs.getInt("roborock_area", 24),
    )
  }

  public fun writeRoborock(context: Context, summary: RoborockSummary) {
    context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putString("roborock_state", summary.state)
        .putInt("roborock_battery", summary.batteryPercent)
        .putString("roborock_room", summary.roomName)
        .putInt("roborock_area", summary.cleanAreaSqm)
        .apply()
  }

  public fun requestComplicationRefresh(context: Context) {
    val intent =
        Intent("android.support.wearable.complications.ACTION_REQUEST_UPDATE_ALL").apply {
          putExtra("android.support.wearable.complications.EXTRA_PACKAGE_NAME", context.packageName)
        }
    context.sendBroadcast(intent)
  }
}

public abstract class BasePulseComplicationService : Service() {
  protected abstract fun currentGauge(): ComplicationGauge

  private val binder =
      object : Binder() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
          if (code == FIRST_CALL_TRANSACTION) {
            val gauge = currentGauge()
            val bundle =
                Bundle().apply {
                  putString("SHORT_TEXT", gauge.shortText)
                  putString("SHORT_TITLE", gauge.title)
                  putString("LONG_TEXT", gauge.longText)
                  putFloat("VALUE", gauge.value)
                  putFloat("MIN_VALUE", gauge.min)
                  putFloat("MAX_VALUE", gauge.max)
                }
            reply?.writeNoException()
            reply?.writeBundle(bundle)
            return true
          }
          return super.onTransact(code, data, reply, flags)
        }
      }

  override fun onBind(intent: Intent?): IBinder = binder
}

public class HomelabPulseComplicationService : BasePulseComplicationService() {
  override fun currentGauge(): ComplicationGauge =
      PulseRepository.readHomelab(applicationContext).deriveGauge()
}

public class MergeQueueComplicationService : BasePulseComplicationService() {
  override fun currentGauge(): ComplicationGauge =
      PulseRepository.readMergeQueue(applicationContext).deriveGauge()
}

public class RoborockPulseComplicationService : BasePulseComplicationService() {
  override fun currentGauge(): ComplicationGauge =
      PulseRepository.readRoborock(applicationContext).deriveGauge()
}
