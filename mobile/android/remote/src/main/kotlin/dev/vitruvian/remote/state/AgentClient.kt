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
package dev.vitruvian.remote.state

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * One reading from the Mac agent's `GET /v1/metrics`.
 *
 * Mirrors the agent's JSON, including its honesty markers: [cpuReady] is false for the first few
 * seconds while `top` samples, and [unavailable] names every figure the agent cannot read without
 * root. A dashboard that ignores either will show a zero as if it were a measurement.
 */
public data class AgentMetrics(
    val cpuReady: Boolean,
    val cpuBusyPercent: Double,
    val load1: Double,
    val memoryUsedBytes: Long,
    val memoryTotalBytes: Long,
    val memoryFreePercent: Int,
    val batteryPresent: Boolean,
    val batteryPercent: Int,
    val onAc: Boolean,
    val charging: Boolean,
    val batteryTemperatureC: Double,
    val drawWatts: Double,
    val diskUsedPercent: Double,
    val rxBytesPerSec: Double,
    val txBytesPerSec: Double,
    val throttled: Boolean,
    val cpuSpeedLimitPercent: Int,
    val uptimeSeconds: Long,
    val unavailable: Set<String>,
)

/** `GET /v1/host`: the slow-changing identity of the machine. */
public data class AgentHost(
    val hostname: String,
    val model: String,
    val chip: String,
    val cores: Int,
    val memoryBytes: Long,
    val osVersion: String,
    val agentVersion: String,
)

/**
 * The phone's side of the read-only agent.
 *
 * Deliberately the platform's own `HttpURLConnection` and `org.json`: two GETs returning small
 * documents do not justify a client library, and this app has no network dependency today.
 * Everything runs on the IO dispatcher; the timeouts are short because a stalled read must show up
 * as "unreachable" within a couple of seconds, not hang a dashboard.
 */
public class AgentClient(baseUrl: String) {
  private val base = normalize(baseUrl)

  public suspend fun metrics(): AgentMetrics =
      withContext(Dispatchers.IO) { parseMetrics(get("/v1/metrics")) }

  public suspend fun host(): AgentHost = withContext(Dispatchers.IO) { parseHost(get("/v1/host")) }

  private fun get(path: String): String {
    val conn = URL(base + path).openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = CONNECT_TIMEOUT_MS
      conn.readTimeout = READ_TIMEOUT_MS
      conn.requestMethod = "GET"
      conn.setRequestProperty("Accept", "application/json")
      if (conn.responseCode != HttpURLConnection.HTTP_OK) {
        throw IllegalStateException("agent: HTTP ${conn.responseCode} for $path")
      }
      return conn.inputStream.bufferedReader().use { it.readText() }
    } finally {
      conn.disconnect()
    }
  }

  public companion object {
    private const val CONNECT_TIMEOUT_MS = 1500
    private const val READ_TIMEOUT_MS = 1500
    public const val DEFAULT_PORT: Int = 7411

    /**
     * Accepts what a person types - `100.124.228.116`, `atlas.coati-koi.ts.net:7411`,
     * `http://atlas:7411/` - and produces a base URL with a scheme and a port and no trailing
     * slash. The port default matches the agent's.
     */
    public fun normalize(input: String): String {
      // ALL whitespace, not just the ends: a phone keyboard auto-inserts a
      // space after "100." and a host can never legitimately contain one.
      var s = input.filterNot { it.isWhitespace() }.trimEnd('/')
      if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://$s"
      val afterScheme = s.substringAfter("://")
      if (!afterScheme.contains(':')) s = "$s:$DEFAULT_PORT"
      return s
    }

    public fun parseMetrics(json: String): AgentMetrics {
      val o = JSONObject(json)
      val cpu = o.getJSONObject("cpu")
      val mem = o.getJSONObject("memory")
      val bat = o.getJSONObject("battery")
      val disk = o.getJSONObject("disk")
      val net = o.getJSONObject("network")
      val th = o.getJSONObject("thermal")
      val un = o.optJSONObject("unavailable")
      return AgentMetrics(
          cpuReady = cpu.optBoolean("ready", false),
          cpuBusyPercent = cpu.optDouble("busy_percent", 0.0),
          load1 = cpu.optDouble("load_1", 0.0),
          memoryUsedBytes = mem.optLong("used_bytes", 0L),
          memoryTotalBytes = mem.optLong("total_bytes", 0L),
          memoryFreePercent = mem.optInt("free_percent", 0),
          batteryPresent = bat.optBoolean("present", false),
          batteryPercent = bat.optInt("percent", 0),
          onAc = bat.optBoolean("on_ac", false),
          charging = bat.optBoolean("charging", false),
          batteryTemperatureC = bat.optDouble("temperature_c", 0.0),
          drawWatts = bat.optDouble("draw_watts", 0.0),
          diskUsedPercent = disk.optDouble("used_percent", 0.0),
          rxBytesPerSec = net.optDouble("rx_bytes_per_sec", 0.0),
          txBytesPerSec = net.optDouble("tx_bytes_per_sec", 0.0),
          throttled = th.optBoolean("throttled", false),
          cpuSpeedLimitPercent = th.optInt("cpu_speed_limit_percent", 100),
          uptimeSeconds = o.optLong("uptime_seconds", 0L),
          unavailable = un?.keys()?.asSequence()?.toSet() ?: emptySet(),
      )
    }

    public fun parseHost(json: String): AgentHost {
      val o = JSONObject(json)
      return AgentHost(
          hostname = o.optString("hostname"),
          model = o.optString("model"),
          chip = o.optString("chip"),
          cores = o.optInt("cores"),
          memoryBytes = o.optLong("memory_bytes"),
          osVersion = o.optString("os_version"),
          agentVersion = o.optString("agent_version"),
      )
    }
  }
}
