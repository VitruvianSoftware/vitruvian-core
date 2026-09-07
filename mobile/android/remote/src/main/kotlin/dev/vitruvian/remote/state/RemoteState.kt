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

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import dev.vitruvian.design.LogEntry
import dev.vitruvian.design.SegState
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.TerminalLine
import dev.vitruvian.design.TerminalTone
import dev.vitruvian.remote.hid.HidAction
import dev.vitruvian.remote.hid.HidCodes
import dev.vitruvian.remote.hid.HidLinkState
import dev.vitruvian.remote.hid.HidSender
import dev.vitruvian.remote.trackpad.TrackpadTuning
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** How often the live metric series advances. */
private const val TICK_MS = 1500L

/** The window of samples the sparks show - 30 samples at 1.5 s is the "60 s" caption. */
public const val SERIES_LENGTH: Int = 30

private const val LOG_LIMIT = 40
private const val TERMINAL_LIMIT = 60

/** Fixed values the prototype states as constants rather than deriving. */
public const val MEMORY_PERCENT: Int = 41
public const val BATTERY_PERCENT: Int = 87
public const val DISK_PERCENT: Int = 60
public const val TRACK_PERCENT: Int = 66

/** Thermals above this read as warn, on both the widget and the Mac screen. */
public const val THERMAL_WARN_C: Int = 75

/**
 * Everything the app knows.
 *
 * A single observable holder rather than a per-screen ViewModel: the screens of this app are views
 * onto one host, and the dock shows two of them at once, so splitting the state would mean plumbing
 * most of it back together.
 */
@Stable
public class RemoteState(
    private val persistence: Persistence,
    initialConnection: Connection = Connection.Connected,
    private val random: Random = Random.Default,
    /**
     * Sends real key presses to a Mac over Bluetooth HID.
     *
     * Null in previews and tests, and null on a device with no host connected -- every call site
     * below treats "not sent" as ordinary, because until the Mac agent exists the mock IS the
     * product for everything this cannot carry.
     */
    private val hid: HidSender? = null,
    /**
     * The phone's clipboard, as a port rather than a `ClipboardManager`.
     *
     * Named for the device it belongs to because [clipboard] below is the Mac's. Null in previews
     * and tests; the push and pull buttons then say so rather than pretending.
     */
    private val phoneClipboard: PhoneClipboard? = null,
    /**
     * Where fire-and-forget actions run.
     *
     * Everything that reaches the Mac over HTTP is a round trip, and none of it may block the frame
     * that dispatched it. A `SupervisorJob` so one failed exec does not cancel the next; the state
     * lives as long as the process, so there is nothing to cancel it from.
     */
    private val scope: CoroutineScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
  // --- navigation -------------------------------------------------------
  public var screen: Screen by mutableStateOf(Screen.Home)
    private set

  public var dockOpen: Boolean by mutableStateOf(persistence.dockOpen)
    private set

  // --- host -------------------------------------------------------------
  public var connection: Connection by mutableStateOf(initialConnection)
    private set

  public var selectedHost: Int by mutableStateOf(persistence.selectedHost)
    private set

  /**
   * A real six-digit code, generated here and offered to the Mac.
   *
   * The phone is the one that invents it: the Mac's `pair` subcommand takes it as an argument, so
   * there is nothing to fetch and nothing to agree on beforehand. Spaced for reading aloud; the
   * digits alone go on the wire.
   */
  public var pairCode: String by mutableStateOf(formatPairCode(random.nextInt(PAIR_CODE_BOUND)))
    private set

  /**
   * Milliseconds left on [pairCode], counted down by the same loop that polls.
   *
   * Observable even though it is private: [pairTtl] is derived from it, and a plain field would
   * leave the countdown on screen frozen at 5:00 while the value underneath it ran out.
   */
  private var pairMillisLeft: Long by mutableStateOf(PAIR_TTL_MS)

  public val pairTtl: String
    get() {
      val seconds = (pairMillisLeft / 1000L).coerceAtLeast(0L)
      return "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
    }

  public var wakeOnLan: Boolean by mutableStateOf(true)
    private set

  public var confirmDestructive: Boolean by mutableStateOf(true)
    private set

  public var tailscaleFirst: Boolean by mutableStateOf(true)
    private set

  public var refreshInterval: String by mutableStateOf("1 s")
    private set

  // --- appearance -------------------------------------------------------
  public var darkTheme: Boolean by mutableStateOf(persistence.darkTheme)
    private set

  // --- home -------------------------------------------------------------
  public var editMode: Boolean by mutableStateOf(false)
    private set

  public val hiddenWidgets: SnapshotStateList<String> =
      persistence.hiddenWidgets.toMutableStateList()

  // --- apps -------------------------------------------------------------
  public var module: String by mutableStateOf("claude")
    private set

  public var appsView: AppsView by mutableStateOf(AppsView.Dashboards)
    private set

  public val installed: SnapshotStateList<String> = persistence.installed.toMutableStateList()

  // --- macros -----------------------------------------------------------
  public val userMacros: SnapshotStateList<Macro> = persistence.userMacros.toMutableStateList()
  public var macroEditorOpen: Boolean by mutableStateOf(false)
    private set

  public var macroName: String by mutableStateOf("")
    private set

  public var macroCommand: String by mutableStateOf("")
    private set

  public var macroKind: MacroKind by mutableStateOf(MacroKind.Ssh)
    private set

  public var macroConfirm: Boolean by mutableStateOf(false)
    private set

  // --- media ------------------------------------------------------------
  public var playing: Boolean by mutableStateOf(true)
    private set

  public var volume: Int by mutableStateOf(62)
    private set

  public var brightness: Int by mutableStateOf(80)
    private set

  public var mirror: Boolean by mutableStateOf(false)
    private set

  // --- trackpad and keys ------------------------------------------------
  /**
   * Whether the Mac is actually reachable.
   *
   * The trackpad's only honest indicator. Without it a connected pad and a dead one are visually
   * identical, and a swipe that does nothing leaves the user guessing between Bluetooth, the app
   * and themselves.
   */
  public var hidLink: HidLinkState by mutableStateOf(HidLinkState.Unavailable)
    private set

  /**
   * The trackpad caption.
   *
   * Derived, never assigned. It used to be set to live finger coordinates -- "412 · 380" -- which
   * are phone pixels: they correspond to nothing on the Mac and change while nobody is looking at
   * them. What the surface knows and the user cannot infer is whether it is connected.
   */
  public val pointerLabel: String
    get() =
        when (hidLink) {
          HidLinkState.Connected -> POINTER_HINT
          HidLinkState.WaitingForHost -> "waiting for atlas…"
          HidLinkState.Unavailable -> "not connected · pair in bluetooth settings"
        }

  public var keyboardOpen: Boolean by mutableStateOf(false)
    private set

  /** Whether the trackpad tuning controls are showing. */
  public var tuningOpen: Boolean by mutableStateOf(false)
    private set

  /**
   * How the trackpad feels.
   *
   * Observable so the controls redraw, and written straight through to [Persistence] on every
   * change: this is tuned by feel, one tap at a time, and a setting that survived only until the
   * next launch would make the whole exercise pointless.
   */
  public var tuning: TrackpadTuning by mutableStateOf(persistence.trackpadTuning)
    private set

  // --- the Mac agent ------------------------------------------------------

  /** Where the agent is; blank means none and the dashboards stay simulated. */
  public var agentUrl: String by mutableStateOf(persistence.agentUrl)
    private set

  /** What the user is typing on the Hosts screen; applied by [applyAgentUrl], not per keystroke. */
  public var agentUrlDraft: String by mutableStateOf(persistence.agentUrl)
    private set

  public var metricsSource: MetricsSource by
      mutableStateOf(
          if (persistence.agentUrl.isBlank()) MetricsSource.Simulated
          else MetricsSource.Unreachable)
    private set

  /** The last reading the agent gave. Kept, frozen, while it is unreachable. */
  public var agentMetrics: AgentMetrics? by mutableStateOf(null)
    private set

  public var agentHost: AgentHost? by mutableStateOf(null)
    private set

  /** Why the last poll failed, for the Hosts screen. Blank while live. */
  public var agentError: String by mutableStateOf("")
    private set

  /**
   * The bearer token pairing issued. Blank means read-only.
   *
   * The whole act half of the contract hangs off this one string: with it the phone can run
   * commands, move the clipboard, set the volume and restart the machine; without it every one of
   * those says "not paired" rather than doing nothing quietly.
   */
  public var agentToken: String by mutableStateOf(persistence.agentToken)
    private set

  public val paired: Boolean
    get() = agentToken.isNotBlank()

  /** [pairCode] as the Mac's `pair` subcommand wants it: six digits, no space. */
  public val pairDigits: String
    get() = pairCode.filterNot { it.isWhitespace() }

  /** en0's address, kept because a sleeping Mac cannot be asked for it. */
  public var agentMac: String by mutableStateOf(persistence.agentMac)
    private set

  // Each of the contract's read endpoints, exactly as it answered. Null means
  // "not asked yet"; an AgentList that says available:false carries the Mac's
  // own reason, and the screens print that instead of an empty list.
  public var agentProcesses: List<AgentProcess>? by mutableStateOf(null)
    private set

  public var agentVms: AgentList<AgentVm>? by mutableStateOf(null)
    private set

  public var agentContainers: AgentList<AgentContainer>? by mutableStateOf(null)
    private set

  public var agentK8s: AgentList<AgentNode>? by mutableStateOf(null)
    private set

  public var agentSessions: AgentSessions? by mutableStateOf(null)
    private set

  /** The Mac's real output volume. The only one of these controls that reads back. */
  public var agentAudio: AgentAudio? by mutableStateOf(null)
    private set

  /**
   * GPU and Neural Engine power, in watts, from `ops/macos-power-agent` via Prometheus.
   *
   * Watts, not percent. There is no "GPU load" figure on Apple silicon that a process can read
   * without root, and the number this replaced was a random walk drawn as a percentage meter -- the
   * most confidently wrong thing on the screen. Null means no Prometheus is configured.
   */
  public var gpuWatts: Double? by mutableStateOf(null)
    private set

  public var aneWatts: Double? by mutableStateOf(null)
    private set

  /** Why there is no power reading, when there is none. */
  public var powerQueryReason: String by mutableStateOf("")
    private set

  public var typed: String by mutableStateOf("")
    private set

  // --- agent and console ------------------------------------------------
  public var prompt: String by mutableStateOf("")
    private set

  public var command: String by mutableStateOf("")
    private set

  public val terminal: SnapshotStateList<TerminalLine> =
      MockHost.initialTerminal.toMutableStateList()
  public val agentTranscript: SnapshotStateList<TerminalLine> =
      MockHost.initialAgentTranscript.toMutableStateList()
  public var agentPaused: Boolean by mutableStateOf(false)
    private set

  /** Commands actually run from this phone, newest first. Persisted. */
  private val ranCommands: SnapshotStateList<String> =
      persistence.recentCommands.toMutableStateList()

  /**
   * The chips under the console input.
   *
   * Real history once there is any; the canned list only while there is none, because an empty row
   * of chips teaches nobody what the console is for.
   */
  public val recentCommands: List<String>
    get() = if (ranCommands.isEmpty()) MockHost.recentCommands else ranCommands.toList()

  public val logs: SnapshotStateList<LogEntry> =
      mutableStateListOf(
          LogEntry("04:37:02", "ok", "homelab · 3/3 nodes ready, no drift"),
          LogEntry("04:36:51", "warn", "lima · k8s-node-3 stopped (manual)"),
          LogEntry("04:36:44", "info", "claude code · session 2 resumed"),
          LogEntry("04:35:10", "ok", "antigravity · build #412 green"),
          LogEntry("04:31:00", "info", "atlas · connected via tailscale (4 ms)"),
      )

  // --- clipboard and power ---------------------------------------------
  public var clipboard: String by
      mutableStateOf("https://github.com/VitruvianSoftware/vitruvian-core/pull/1551")
    private set

  public var dialog: DialogKind? by mutableStateOf(null)
    private set

  public var confirmText: String by mutableStateOf("")
    private set

  // --- PromQL panel -----------------------------------------------------
  public var promql: String by mutableStateOf("rate(node_cpu_seconds_total{mode!=\"idle\"}[5m])")
    private set

  public var promqlStatus: String by mutableStateOf("panel preview · run query")
    private set

  // --- live series ------------------------------------------------------
  public val cpu: SnapshotStateList<Int> =
      List(SERIES_LENGTH) { 18 + (12 * abs(sin(it / 3.0))).roundToInt() }.toMutableStateList()
  public val net: SnapshotStateList<Int> =
      List(SERIES_LENGTH) { 10 + (40 * abs(sin(it / 2.2))).roundToInt() }.toMutableStateList()
  public var gpu: Int by mutableStateOf(31)
    private set

  public var ane: Int by mutableStateOf(12)
    private set

  public var temperature: Int by mutableStateOf(48)
    private set

  public var fanRpm: Int by mutableStateOf(1200)
    private set

  public var powerDraw: Int by mutableStateOf(18)
    private set

  // --- derived ----------------------------------------------------------

  /** Navigation is locked to Hosts until a Mac is paired. */
  public val effectiveScreen: Screen
    get() = if (connection == Connection.Unpaired) Screen.Hosts else screen

  public val isOffline: Boolean
    get() = connection == Connection.Offline

  public val isUnpaired: Boolean
    get() = connection == Connection.Unpaired

  public val hosts: List<Host>
    get() =
        if (isUnpaired) {
          emptyList()
        } else {
          // Once an agent has answered, the list is exactly the machine it
          // answered for. `forge` is a mock, and a mock host sitting under a
          // real one reads as a second Mac that happens to be asleep.
          MockHost.hosts.take(if (agentHost != null) 1 else MockHost.hosts.size).mapIndexed {
              index,
              host ->
            val live = agentHost
            if (index == 0 && live != null) {
              Host(
                  id = host.id,
                  name = "${live.hostname} · ${live.chip}",
                  subtitle =
                      "${agentHostLabel()} · macOS ${live.osVersion} · ${(live.memoryBytes / GIB).roundToInt()} GB",
                  tone =
                      if (metricsSource == MetricsSource.Live) StatusTone.Ok else StatusTone.Crit,
                  tag = metricsSource.label,
                  tagTone =
                      if (metricsSource == MetricsSource.Live) TagTone.Ok else TagTone.Sanguine,
              )
            } else if (index == 0 && isOffline) {
              host.copy(
                  subtitle = MockHost.OFFLINE_SUBTITLE,
                  tag = "unreachable",
                  tagTone = TagTone.Sanguine,
              )
            } else {
              host
            }
          }
        }

  /** The short name the top bar and rail show - `atlas`, not the full row title. */
  public val hostShortName: String
    get() =
        if (isUnpaired) {
          "no host"
        } else {
          hosts.getOrNull(selectedHost)?.name?.substringBefore(" · ") ?: "no host"
        }

  /** The chip's text: the short name, suffixed when unreachable. */
  public val hostChipText: String
    get() =
        when {
          isUnpaired -> "no host"
          isOffline -> "$hostShortName · offline"
          else -> hostShortName
        }

  public val hostTone: StatusTone
    get() =
        when (connection) {
          Connection.Connected -> StatusTone.Ok
          Connection.Offline -> StatusTone.Crit
          Connection.Unpaired -> StatusTone.Neutral
        }

  public val connectionWord: String
    get() =
        when (connection) {
          Connection.Connected -> "connected"
          Connection.Offline -> "unreachable"
          Connection.Unpaired -> "unpaired"
        }

  /** The line under the host name on Home: real when the agent has answered, the mock otherwise. */
  public val hostSubline: String
    get() {
      val h = agentHost ?: return "macOS 26.1 · Tailscale · 4 ms"
      val up = agentMetrics?.uptimeSeconds ?: 0L
      val days = up / SECONDS_PER_DAY
      return "macOS ${h.osVersion} · agent v${h.agentVersion} · up ${days}d"
    }

  public val metricsTagTone: TagTone
    get() =
        when (metricsSource) {
          MetricsSource.Live -> TagTone.Ok
          MetricsSource.Unreachable -> TagTone.Sanguine
          MetricsSource.Simulated -> TagTone.Outline
        }

  /** The host part of the configured agent URL, for display. */
  private fun agentHostLabel(): String =
      AgentClient.normalize(agentUrl).substringAfter("://").substringBefore('/')

  /**
   * Whether what is on screen came from the Mac.
   *
   * The single switch every "live or mock" decision below turns on. Unreachable is deliberately NOT
   * live: the last reading stays frozen on screen and tagged, but nothing derives new claims from
   * it -- a process list from four minutes ago presented as the process list is a lie with a
   * timestamp.
   */
  public val isLive: Boolean
    get() = metricsSource == MetricsSource.Live

  // --- the Mac screen, live or mock -------------------------------------
  //
  // Each pair is (rows, notice). A non-null notice means the agent could not
  // produce the list and said why; the screen prints the reason IN PLACE OF
  // the rows, which is the contract's own rule. A list that is merely empty
  // is still shown as empty -- "no containers running" is a real answer.

  public val processes: List<Process>
    get() {
      if (!isLive) return MockHost.processes
      return agentProcesses.orEmpty().map {
        Process(
            name = it.name,
            cpu = it.cpuPercent.roundToInt(),
            memory = formatBytes(it.memoryBytes),
        )
      }
    }

  public val processesNotice: String?
    get() = if (isLive && agentProcesses == null) "sampling…" else null

  public val vms: List<Vm>
    get() {
      val live = agentVms
      if (!isLive || live == null || !live.available)
          return if (isLive) emptyList() else MockHost.vms
      return live.items.map { vm ->
        val running = vm.status.equals("Running", ignoreCase = true)
        Vm(
            name = vm.name,
            subtitle =
                "${vm.arch} · ${vm.cpus} cpu · ${formatBytes(vm.memoryBytes)} · ${vm.vmType}",
            tone = if (running) StatusTone.Ok else StatusTone.Warn,
            tag = vm.status.lowercase(Locale.ROOT),
            tagTone = if (running) TagTone.Ok else TagTone.Warn,
        )
      }
    }

  public val vmsNotice: String?
    get() = liveNotice(agentVms, "limactl")

  public val containers: List<Container>
    get() {
      val live = agentContainers
      if (!isLive || live == null || !live.available) {
        return if (isLive) emptyList() else MockHost.containers
      }
      return live.items.map { Container(it.name, it.image, it.status) }
    }

  public val containersNotice: String?
    get() = liveNotice(agentContainers, "docker / podman")

  /**
   * The K3s nodes, which used to share a section with the Lima VMs.
   *
   * They are separate endpoints with separate failure modes: `limactl` can be missing while
   * `kubectl` works, and one list showing both could only report the worse of the two.
   */
  public val nodes: List<Vm>
    get() {
      val live = agentK8s
      if (!isLive || live == null || !live.available) return emptyList()
      return live.items.map { node ->
        Vm(
            name = node.name,
            subtitle = "${node.roles.joinToString(", ").ifBlank { "no role" }} · ${node.version}",
            tone = if (node.ready) StatusTone.Ok else StatusTone.Crit,
            tag = if (node.ready) "ready" else "not ready",
            tagTone = if (node.ready) TagTone.Ok else TagTone.Sanguine,
        )
      }
    }

  public val nodesNotice: String?
    get() =
        if (!isLive) "simulated · no cluster behind this screen"
        else liveNotice(agentK8s, "kubectl")

  /** The section header, which carries the count and so must not invent one. */
  public val containersLabel: String
    get() {
      val live = agentContainers
      if (!isLive) return "Docker · ${MockHost.containers.size} containers"
      if (live == null) return "Containers"
      if (!live.available) return "Containers · unavailable"
      val runtime = live.detail.ifBlank { "containers" }
      return "$runtime · ${live.items.size} running"
    }

  /**
   * GPU and Neural Engine, as the Mac can actually report them.
   *
   * A percentage meter is deliberately absent here. Watts are not a fraction of anything the phone
   * knows, and the meter that used to sit under these numbers was drawing a random walk.
   */
  public val gpuPlate: HonestMetric
    get() = powerPlate("GPU", gpu, "Metal · 2 clients", gpuWatts)

  public val anePlate: HonestMetric
    get() = powerPlate("Neural Engine", ane, "ollama · llama3.3", aneWatts)

  private fun powerPlate(
      label: String,
      simulated: Int,
      simulatedSub: String,
      watts: Double?,
  ): HonestMetric =
      when {
        !isLive -> HonestMetric(label, "$simulated%", simulatedSub, simulated)
        watts != null -> HonestMetric(label, "${"%.1f".format(watts)} W", "power, not load", null)
        else -> HonestMetric(label, "n/a", powerQueryReason.ifBlank { POWER_UNAVAILABLE }, null)
      }

  /**
   * Thermals on the Mac screen, mirroring the Home widget rather than contradicting it.
   *
   * Two tiles claiming different temperatures for one machine is worse than one tile saying it
   * cannot read the SoC, which is the truth: there is no die temperature and no fan speed without
   * root, so this reports throttling state and the battery's own sensor.
   */
  public val thermalPlate: HonestMetric
    get() {
      val m = agentMetrics
      if (!isLive || m == null) {
        return HonestMetric(
            "Thermals",
            "$temperature°",
            "fans $fanRpm rpm",
            temperature,
            warn = temperature > THERMAL_WARN_C,
        )
      }
      return HonestMetric(
          label = "Thermals",
          value = if (m.throttled) "${m.cpuSpeedLimitPercent}%" else "ok",
          sub = "battery ${"%.1f".format(m.batteryTemperatureC)}° · SoC n/a · fans n/a",
          percent = if (m.throttled) 100 - m.cpuSpeedLimitPercent else null,
          warn = m.throttled,
      )
    }

  /**
   * The per-core split under the CPU spark.
   *
   * `top` reports one busy figure for the machine, not a P/E split -- that needs `powermetrics` and
   * root. The line said "P-cores 34% · E-cores 12%" for numbers nothing had ever measured.
   */
  public val cpuBreakdown: String
    get() {
      if (!isLive) return "P-cores 34% · E-cores 12%"
      val m = agentMetrics ?: return "sampling…"
      return "load ${"%.2f".format(m.load1)} · P/E split n/a"
    }

  public val memoryPlate: HonestMetric
    get() {
      val m = agentMetrics
      if (!isLive || m == null) {
        return HonestMetric(
            "Memory pressure", "$MEMORY_PERCENT%", "26.4 / 64 GB · swap 0 B", MEMORY_PERCENT)
      }
      val pressure = (100 - m.memoryFreePercent).coerceIn(0, 100)
      return HonestMetric(
          label = "Memory pressure",
          value = "$pressure%",
          sub =
              "${formatBytes(m.memoryUsedBytes)} / ${formatBytes(m.memoryTotalBytes)} · " +
                  "swap n/a",
          percent = pressure,
      )
    }

  /** app / wired / compressed / cached, which `vm_stat` gives and this agent does not read. */
  public val memoryBreakdown: List<String>
    get() =
        if (isLive) listOf("app, wired, compressed and cached: not read by this agent")
        else listOf("app 18.1 GB", "wired 4.2 GB", "compressed 2.1 GB", "cached 12 GB")

  public val batteryPlate: HonestMetric
    get() {
      val m = agentMetrics
      if (!isLive || m == null) {
        return HonestMetric("Battery", "$BATTERY_PERCENT%", "$powerDraw W · on AC", BATTERY_PERCENT)
      }
      if (!m.batteryPresent) return HonestMetric("Battery", "n/a", "no battery", null)
      return HonestMetric(
          label = "Battery",
          value = "${m.batteryPercent}%",
          sub =
              "${m.drawWatts.roundToInt()} W · " +
                  when {
                    m.charging -> "charging"
                    m.onAc -> "on AC"
                    else -> "on battery"
                  },
          percent = m.batteryPercent,
          warn = !m.onAc && m.batteryPercent < BATTERY_WARN_PERCENT,
      )
    }

  public val diskPlate: HonestMetric
    get() {
      val m = agentMetrics
      if (!isLive || m == null) {
        return HonestMetric(
            "Disk · Macintosh HD", "1.21 / 2 TB", "R 42 MB/s · W 8 MB/s", DISK_PERCENT)
      }
      val used = m.diskUsedPercent.roundToInt()
      return HonestMetric(
          label = "Disk",
          value = "$used%",
          sub = "used · throughput n/a",
          percent = used,
      )
    }

  /** What the console is actually talking to. */
  public val consoleSubtitle: String
    get() =
        when {
          agentUrl.isBlank() -> "zsh · no agent configured"
          else -> "zsh -lc · ${agentHost?.hostname ?: agentHostLabel()} · via the agent"
        }

  /** Where a PromQL query would go, named rather than asserted. */
  public val promqlSource: String
    get() =
        when {
          agentUrl.isBlank() -> "source · none · configure the agent on Hosts"
          else -> "source · ${agentHostLabel()} · proxied to the agent's --prometheus-url"
        }

  /** The Mac screen's header line. */
  public val computeSubline: String
    get() {
      val h = agentHost ?: return "Apple M4 Max · 16c CPU · 40c GPU · 64 GB"
      return "${h.model} · ${h.chip} · ${h.cores} cores · " +
          "${(h.memoryBytes / GIB).roundToInt()} GB"
    }

  // --- media --------------------------------------------------------------

  /**
   * What is playing, when anything can say so.
   *
   * Nothing can. macOS exposes no now-playing information to a shell without private frameworks or
   * an extra helper, so the plate says that in as many words rather than keeping a track title that
   * was invented in a mock. The transport buttons underneath are real HID and stay.
   */
  public val mediaTitle: String
    get() = if (isLive) "Now playing · n/a" else if (playing) "Ambient Works 85–92" else "Paused"

  public val mediaSub: String
    get() = if (isLive) "no public API without extra tools" else "2:41 / 4:03"

  /** The volume the MAC reports, not the one we guessed. Null when nothing has said. */
  public val volumeValue: String
    get() {
      if (!isLive) return "$volume%"
      val a = agentAudio ?: return "n/a"
      return if (a.muted) "muted" else "${a.volumePercent}%"
    }

  public val volumeFraction: Float?
    get() = if (!isLive) volume / 100f else agentAudio?.let { it.volumePercent / 100f }

  /**
   * Brightness has no read source at all.
   *
   * There is no `pmset`-style display brightness the agent could read on an external or built-in
   * panel without extra tooling, so the keys stay -- they work over HID -- and the number goes
   * away, because the local guess was drifting further from the real value with every press.
   */
  public val brightnessValue: String
    get() = if (isLive) "n/a" else "$brightness%"

  public val brightnessFraction: Float?
    get() = if (isLive) null else brightness / 100f

  private fun <T> liveNotice(list: AgentList<T>?, tool: String): String? =
      when {
        !isLive -> null
        list == null -> "asking $tool…"
        !list.available -> list.reason.ifBlank { "$tool unavailable, and it did not say why" }
        else -> null
      }

  /** User macros come first, so a just-saved one is where the author left it. */
  public val macros: List<Macro>
    get() = userMacros + MockHost.builtInMacros

  public val widgets: List<Widget>
    get() =
        (agentMetrics?.let(::liveWidgets) ?: simulatedWidgets).filterNot { it.id in hiddenWidgets }

  /**
   * Widgets from a real reading.
   *
   * Every figure the agent marks unavailable is labelled so on the widget rather than left as a
   * plausible-looking zero: there is no SoC temperature and no fan speed without root, so the
   * thermal tile shows throttling state and the battery's own sensor instead.
   */
  private fun liveWidgets(m: AgentMetrics): List<Widget> {
    val h = agentHost
    val gb = { bytes: Long -> "%.1f".format(bytes / GIB) }
    val pressure = (100 - m.memoryFreePercent).coerceIn(0, 100)
    val cpuValue = if (m.cpuReady) "${m.cpuBusyPercent.roundToInt()}%" else "…"
    val cpuSub =
        when {
          !m.cpuReady -> "sampling…"
          h != null -> "${h.chip} · ${h.cores} cores"
          else -> "load ${"%.2f".format(m.load1)}"
        }
    val thermalValue = if (m.throttled) "${m.cpuSpeedLimitPercent}%" else "ok"
    val thermalSub = "battery ${"%.1f".format(m.batteryTemperatureC)}° · SoC n/a"
    val batValue = if (m.batteryPresent) "${m.batteryPercent}%" else "n/a"
    val batSub =
        when {
          !m.batteryPresent -> "no battery"
          m.charging -> "${powerDraw} W · charging"
          m.onAc -> "on AC"
          else -> "${powerDraw} W · on battery"
        }
    return listOf(
        Widget(
            "cpu", "CPU", cpuValue, cpuSub, if (m.cpuReady) m.cpuBusyPercent.roundToInt() else 0),
        Widget(
            "mem",
            "Memory pressure",
            "$pressure%",
            "${gb(m.memoryUsedBytes)} / ${gb(m.memoryTotalBytes)} GB used",
            pressure),
        Widget(
            id = "temp",
            label = "Thermals",
            value = thermalValue,
            sub = thermalSub,
            percent = if (m.throttled) 100 - m.cpuSpeedLimitPercent else 0,
            warn = m.throttled,
        ),
        Widget(
            "bat",
            "Battery",
            batValue,
            batSub,
            if (m.batteryPresent) m.batteryPercent else 0,
            warn = m.batteryPresent && !m.onAc && m.batteryPercent < BATTERY_WARN_PERCENT,
        ),
    )
  }

  private val simulatedWidgets: List<Widget>
    get() =
        listOf(
            Widget("cpu", "CPU", "${cpu.last()}%", "M4 Max · 16 cores", cpu.last()),
            Widget("mem", "Memory pressure", "$MEMORY_PERCENT%", "26.4 / 64 GB", MEMORY_PERCENT),
            Widget(
                id = "temp",
                label = "Thermals",
                value = "$temperature°",
                sub = "fans $fanRpm rpm",
                percent = temperature,
                warn = temperature > THERMAL_WARN_C,
            ),
            Widget("bat", "Battery", "$BATTERY_PERCENT%", "$powerDraw W · on AC", BATTERY_PERCENT),
        )

  /**
   * What is actually running, when the Mac can say.
   *
   * Every row here is derived from an endpoint, and a row whose endpoint said `available:false`
   * carries that reason as its subtitle instead of a count. Antigravity has no source on this
   * machine at all, so in live mode it is absent rather than green -- an item nobody is measuring
   * should not be sitting in a list called "Running now".
   */
  public val runningNow: List<RunningItem>
    get() {
      if (!isLive) return MockHost.runningNow
      val rows = mutableListOf<RunningItem>()
      agentSessions?.let { s ->
        val idle = s.sessions.isEmpty() && s.runningProcesses == 0
        rows +=
            RunningItem(
                moduleId = "claude",
                title = "Claude Code",
                subtitle =
                    "${s.sessions.size} session${plural(s.sessions.size)} · " +
                        "${s.runningProcesses} process${if (s.runningProcesses == 1) "" else "es"}",
                tone = if (idle) StatusTone.Neutral else StatusTone.Run,
                tag = if (idle) "idle" else "running",
                tagTone = if (idle) TagTone.Neutral else TagTone.Accent,
            )
      }
      agentVms?.let { v ->
        val running = v.items.count { it.status.equals("Running", ignoreCase = true) }
        val stopped = v.items.size - running
        rows +=
            RunningItem(
                moduleId = "lima",
                title = "Lima VMs",
                subtitle = if (v.available) "$running running · $stopped stopped" else v.reason,
                tone =
                    when {
                      !v.available -> StatusTone.Neutral
                      stopped > 0 -> StatusTone.Warn
                      else -> StatusTone.Ok
                    },
                tag =
                    when {
                      !v.available -> "no source"
                      stopped > 0 -> "$stopped down"
                      else -> "ready"
                    },
                tagTone =
                    when {
                      !v.available -> TagTone.Outline
                      stopped > 0 -> TagTone.Warn
                      else -> TagTone.Ok
                    },
            )
      }
      agentK8s?.let { k ->
        val ready = k.items.count { it.ready }
        rows +=
            RunningItem(
                moduleId = "homelab",
                title = "Homelab · K3s",
                subtitle =
                    if (k.available) "$ready/${k.items.size} nodes ready · ${k.detail}"
                    else k.reason,
                tone =
                    when {
                      !k.available -> StatusTone.Neutral
                      ready == k.items.size && ready > 0 -> StatusTone.Ok
                      else -> StatusTone.Warn
                    },
                tag = if (k.available) "$ready/${k.items.size}" else "no source",
                tagTone =
                    when {
                      !k.available -> TagTone.Outline
                      ready == k.items.size && ready > 0 -> TagTone.Ok
                      else -> TagTone.Warn
                    },
            )
      }
      agentContainers?.let { c ->
        rows +=
            RunningItem(
                moduleId = "docker",
                title = c.detail.ifBlank { "Containers" }.replaceFirstChar { it.uppercase() },
                subtitle =
                    if (c.available) "${c.items.size} container${plural(c.items.size)}"
                    else c.reason,
                tone = if (c.available) StatusTone.Ok else StatusTone.Neutral,
                tag = if (c.available) "${c.items.size}" else "no source",
                tagTone = if (c.available) TagTone.Ok else TagTone.Outline,
            )
      }
      return rows
    }

  public val moduleDashboards: Map<String, ModuleDashboard>
    get() {
      val mocked = MockHost.dashboards(agentTranscript.toList(), !agentPaused)
      if (!isLive) return mocked
      // Every installed module gets a dashboard in live mode, including the
      // ones nothing on this Mac feeds. Dropping those would leave the chip
      // row looking arbitrary; showing the mock would be a fabrication. They
      // get an honest empty one instead.
      val ids = MockHost.gallery.map { it.id }
      return ids.associateWith { id -> liveDashboard(id) ?: unwiredDashboard(id) }
    }

  /** The four modules that have a real source on this machine. */
  private fun liveDashboard(id: String): ModuleDashboard? =
      when (id) {
        "claude" -> claudeDashboard()
        "lima" -> limaDashboard()
        "homelab" -> homelabDashboard()
        "docker" -> dockerDashboard()
        else -> null
      }

  private fun claudeDashboard(): ModuleDashboard {
    val s = agentSessions
    return ModuleDashboard(
        id = "claude",
        name = "Claude Code",
        meta = "~/.claude/projects · ${agentHost?.hostname ?: "host"}",
        status = if ((s?.runningProcesses ?: 0) > 0) "running" else "idle",
        statusTone = if ((s?.runningProcesses ?: 0) > 0) StatusTone.Run else StatusTone.Neutral,
        metrics =
            listOf(
                ModuleMetric("Sessions", "${s?.sessions?.size ?: 0}", "active in the last 30 min"),
                ModuleMetric("Processes", "${s?.runningProcesses ?: 0}", "argv[0] is claude"),
                // Named rather than dropped: a missing tile invites the
                // assumption that we simply forgot it.
                ModuleMetric("Tokens today", "n/a", "not exposed by the CLI"),
            ),
        streamLabel = "Transcript · this phone",
        // The phone's own exchanges, not the Mac's. Only prompts sent from
        // here are on this transcript, and the label says so.
        lines = agentTranscript.toList(),
        cursor = !agentPaused,
        prompts = true,
        listLabel = "Sessions",
        rows =
            s?.sessions?.map { ModuleRow(it.project, it.path, it.lastActive, StatusTone.Run) }
                ?: emptyList(),
    )
  }

  private fun limaDashboard(): ModuleDashboard {
    val v = agentVms
    val running = v?.items?.count { it.status.equals("Running", ignoreCase = true) } ?: 0
    val available = v?.available == true
    return ModuleDashboard(
        id = "lima",
        name = "Lima VMs",
        meta = "limactl list",
        status = if (available) "$running of ${v?.items?.size ?: 0} running" else "no source",
        statusTone = if (available) StatusTone.Ok else StatusTone.Neutral,
        metrics =
            listOf(
                ModuleMetric(
                    "Running", if (available) "$running" else "n/a", "of ${v?.items?.size ?: 0}"),
                ModuleMetric(
                    "vCPU",
                    if (available) "${v?.items?.sumOf { it.cpus } ?: 0}" else "n/a",
                    "allocated"),
                ModuleMetric(
                    "Memory",
                    if (available) formatBytes(v?.items?.sumOf { it.memoryBytes } ?: 0L) else "n/a",
                    "allocated"),
            ),
        streamLabel = "limactl list",
        lines = summaryLines("limactl list", v) { "${it.name}  ${it.status}  ${it.arch}" },
        cursor = false,
        prompts = false,
        listLabel = "Instances",
        rows =
            v?.items?.map { vm ->
              ModuleRow(
                  vm.name,
                  "${vm.arch} · ${vm.cpus} cpu · ${formatBytes(vm.memoryBytes)}",
                  vm.status.lowercase(Locale.ROOT),
                  if (vm.status.equals("Running", ignoreCase = true)) StatusTone.Ok
                  else StatusTone.Warn,
              )
            } ?: emptyList(),
    )
  }

  private fun homelabDashboard(): ModuleDashboard {
    val k = agentK8s
    val ready = k?.items?.count { it.ready } ?: 0
    val total = k?.items?.size ?: 0
    val available = k?.available == true
    return ModuleDashboard(
        id = "homelab",
        name = "Homelab · K3s",
        meta = if (available) "kubectl · ${k?.detail}" else "kubectl",
        status = if (available) "$ready/$total ready" else "no source",
        statusTone =
            when {
              !available -> StatusTone.Neutral
              ready == total && total > 0 -> StatusTone.Ok
              else -> StatusTone.Warn
            },
        metrics =
            listOf(
                ModuleMetric("Nodes", if (available) "$ready/$total" else "n/a", "ready / total"),
                ModuleMetric("Context", k?.detail?.ifBlank { "n/a" } ?: "n/a", "--kube-context"),
                ModuleMetric("Workloads", "n/a", "not read by this agent"),
            ),
        streamLabel = "kubectl get nodes",
        lines =
            summaryLines("kubectl get nodes", k) {
              "${it.name}  ${if (it.ready) "Ready" else "NotReady"}  ${it.version}"
            },
        cursor = false,
        prompts = false,
        listLabel = "Nodes",
        rows =
            k?.items?.map { node ->
              ModuleRow(
                  node.name,
                  "${node.roles.joinToString(",").ifBlank { "no role" }} · ${node.version}",
                  if (node.ready) "ready" else "not ready",
                  if (node.ready) StatusTone.Ok else StatusTone.Crit,
              )
            } ?: emptyList(),
    )
  }

  private fun dockerDashboard(): ModuleDashboard {
    val c = agentContainers
    val available = c?.available == true
    val runtime = c?.detail?.ifBlank { "docker" } ?: "docker"
    return ModuleDashboard(
        id = "docker",
        name = "Docker",
        meta = "$runtime ps",
        status = if (available) "${c?.items?.size ?: 0} running" else "no source",
        statusTone = if (available) StatusTone.Ok else StatusTone.Neutral,
        metrics =
            listOf(
                ModuleMetric(
                    "Containers",
                    if (available) "${c?.items?.size ?: 0}" else "n/a",
                    "running now"),
                ModuleMetric("Runtime", if (available) runtime else "n/a", "docker or podman"),
                ModuleMetric("CPU", "n/a", "needs docker stats"),
            ),
        streamLabel = "$runtime ps",
        lines = summaryLines("$runtime ps", c) { "${it.name}  ${it.image}  ${it.status}" },
        cursor = false,
        prompts = false,
        listLabel = "Containers",
        rows =
            c?.items?.map { ModuleRow(it.name, it.image, it.status, StatusTone.Ok) } ?: emptyList(),
    )
  }

  /**
   * The dashboard for a module with nothing behind it on this Mac.
   *
   * Says exactly that, and names the source the gallery advertises, so the reason it is empty is on
   * the screen rather than in someone's head. The alternative -- keeping the mock -- puts invented
   * build numbers next to real ones and nothing distinguishes them.
   */
  private fun unwiredDashboard(id: String): ModuleDashboard {
    val entry = MockHost.gallery.firstOrNull { it.id == id }
    return ModuleDashboard(
        id = id,
        name = entry?.name ?: id,
        meta = entry?.subtitle.orEmpty(),
        status = "no data source yet",
        statusTone = StatusTone.Neutral,
        metrics = listOf(ModuleMetric("Source", entry?.source ?: "unknown", "what it would use")),
        streamLabel = "Stream",
        lines = emptyList(),
        cursor = false,
        prompts = false,
        listLabel = entry?.name ?: id,
        rows =
            listOf(
                ModuleRow(
                    "Not wired to this Mac yet",
                    "the agent has no endpoint for it",
                    "n/a",
                    StatusTone.Neutral,
                )),
    )
  }

  /** A command line plus one line per row, or the reason there are none. */
  private fun <T> summaryLines(
      command: String,
      list: AgentList<T>?,
      row: (T) -> String,
  ): List<TerminalLine> {
    val head = TerminalLine("$", command, TerminalTone.Text)
    if (list == null) return listOf(head, TerminalLine(" ", "asking…", TerminalTone.Dim))
    if (!list.available) {
      return listOf(head, TerminalLine(" ", list.reason, TerminalTone.Warn))
    }
    if (list.items.isEmpty()) {
      return listOf(head, TerminalLine(" ", "no rows", TerminalTone.Dim))
    }
    return listOf(head) + list.items.map { TerminalLine(" ", row(it), TerminalTone.Dim) }
  }

  /** Only installed modules that actually ship a dashboard get a chip. */
  public val moduleChips: List<GalleryEntry>
    get() = MockHost.gallery.filter { it.id in installed && it.id in moduleDashboards }

  public val currentModule: ModuleDashboard
    get() = moduleDashboards[module] ?: moduleDashboards.getValue("claude")

  /**
   * The memory bar, filled from the pressure figure above it rather than from a constant.
   *
   * It used to be a fixed 7-on, 2-warn pattern sitting directly under a percentage it never
   * matched: the number could read 41% or 88% and the bar looked identical.
   */
  public val memorySegments: List<SegState>
    get() {
      val pressure = (memoryPlate.percent ?: 0).coerceIn(0, 100)
      val lit = MEMORY_SEGMENTS * pressure / 100
      val warnFrom = MEMORY_SEGMENTS * MEMORY_WARN_PERCENT / 100
      return List(MEMORY_SEGMENTS) { index ->
        when {
          index >= lit -> SegState.Empty
          index >= warnFrom -> SegState.Warn
          else -> SegState.On
        }
      }
    }

  public val networkDown: String
    get() = "${(net.last() * DOWN_FACTOR).roundToInt()} Mb/s"

  public val networkUp: String
    get() = "${(net.last() * UP_FACTOR).roundToInt()} Mb/s"

  /** The dialog currently open, resolved to its copy. */
  public val dialogSpec: DialogSpec?
    get() = dialog?.let { DialogSpec.of(it, wakeOnLan, confirmDestructive) }

  /** A destructive dialog's action stays disabled until the word is typed exactly. */
  public val dialogBlocked: Boolean
    get() {
      val word = dialogSpec?.word ?: return false
      return confirmText.trim().lowercase(Locale.ROOT) != word
    }

  public val macroSaveBlocked: Boolean
    get() = macroName.isBlank() || macroCommand.isBlank()

  // --- the tick ---------------------------------------------------------

  /**
   * Advances the live series until cancelled.
   *
   * A random walk clamped to plausible bounds, matching the prototype's shape; the point of the
   * motion is that the dashboards read as live, not that the numbers mean anything yet.
   */
  public suspend fun runMetrics() {
    while (true) {
      val step = if (agentUrl.isBlank()) TICK_MS else refreshMillis
      delay(step)
      // Counted from the delay actually taken rather than from a wall clock:
      // the code's five minutes are five minutes of this loop, which is the
      // only thing that can ask the Mac for the token.
      tickPairing(step)
      if (agentUrl.isBlank()) advance() else pollAgent()
    }
  }

  /**
   * How often to ask, honouring the Hosts screen's setting.
   *
   * Only when an agent is configured. The simulated walk keeps its own cadence: the setting is
   * about how hard to lean on a real machine, and there is nothing to lean on otherwise.
   */
  private val refreshMillis: Long
    get() =
        refreshInterval
            .filter { it.isDigit() }
            .toLongOrNull()
            ?.times(1000L)
            ?.coerceAtLeast(MIN_POLL_MS) ?: TICK_MS

  /**
   * Runs the pairing code's clock down, and offers the code to the Mac while it lasts.
   *
   * The phone polls rather than the Mac pushing, because the Mac has nowhere to push to: the agent
   * is a server on the tailnet and the phone is not. A 403 is the ordinary answer until someone
   * runs the `pair` subcommand, so it is not logged -- it would be a warning every tick for as long
   * as the code is on screen.
   */
  private suspend fun tickPairing(elapsedMs: Long) {
    if (pairMillisLeft > 0) pairMillisLeft = (pairMillisLeft - elapsedMs).coerceAtLeast(0)
    if (agentUrl.isBlank() || paired || pairMillisLeft <= 0) return
    val token = runCatching { AgentClient(agentUrl).pair(pairCode) }.getOrNull() ?: return
    agentToken = token
    persistence.agentToken = token
    log("ok", "pairing · paired with ${agentHost?.hostname ?: agentHostLabel()}")
  }

  private fun advance() {
    cpu.removeAt(0)
    cpu.add((cpu.last() + walk(CPU_STEP)).coerceIn(CPU_MIN, CPU_MAX))
    net.removeAt(0)
    net.add((net.last() + walk(NET_STEP)).coerceIn(NET_MIN, NET_MAX))
    gpu = (gpu + walk(GPU_STEP)).coerceIn(GPU_MIN, GPU_MAX)
    ane = (ane + walk(ANE_STEP)).coerceIn(0, ANE_MAX)
    temperature = (temperature + walk(TEMP_STEP)).coerceIn(TEMP_MIN, TEMP_MAX)
    fanRpm = FAN_BASE + temperature * FAN_PER_DEGREE
    powerDraw = DRAW_BASE + cpu.last() / DRAW_DIVISOR
  }

  private fun walk(step: Int): Int = ((random.nextDouble() - 0.5) * step).roundToInt()

  // --- actions ----------------------------------------------------------

  public fun go(target: Screen) {
    screen = target
  }

  public fun openModule(id: String) {
    module = id
    appsView = AppsView.Dashboards
    screen = Screen.Apps
  }

  public fun selectModule(id: String) {
    module = id
  }

  public fun showAppsView(view: AppsView) {
    appsView = view
  }

  public fun toggleDock() {
    dockOpen = !dockOpen
    persistence.dockOpen = dockOpen
  }

  public fun toggleEditMode() {
    editMode = !editMode
  }

  public fun hideWidget(id: String) {
    if (id !in hiddenWidgets) {
      hiddenWidgets.add(id)
      persistence.hiddenWidgets = hiddenWidgets.toList()
    }
  }

  public fun restoreWidgets() {
    hiddenWidgets.clear()
    persistence.hiddenWidgets = emptyList()
  }

  public fun selectHost(id: Int) {
    selectedHost = id
    persistence.selectedHost = id
  }

  public fun toggleTheme() {
    darkTheme = !darkTheme
    persistence.darkTheme = darkTheme
  }

  public fun updateTailscaleFirst(value: Boolean) {
    tailscaleFirst = value
  }

  public fun updateWakeOnLan(value: Boolean) {
    wakeOnLan = value
  }

  public fun updateConfirmDestructive(value: Boolean) {
    confirmDestructive = value
  }

  public fun updateRefreshInterval(value: String) {
    refreshInterval = value
  }

  public fun regeneratePairCode() {
    pairCode = formatPairCode(random.nextInt(PAIR_CODE_BOUND))
    pairMillisLeft = PAIR_TTL_MS
  }

  public fun toggleModule(id: String) {
    val name = MockHost.gallery.first { it.id == id }.name
    if (id in installed) {
      installed.remove(id)
      log("info", "module · $name removed")
    } else {
      installed.add(id)
      log("ok", "module · $name installed")
    }
    persistence.installed = installed.toList()
  }

  public fun sideload(): Unit = log("info", "module · sideload dialog")

  public fun openInstallGuide(): Unit = log("info", "pairing · install guide opened")

  /**
   * Runs a macro on the Mac.
   *
   * This used to print `ok — done` unconditionally, which was a lie in the one case that matters:
   * when nothing ran. Now either the command's real output lands in the console, or the log says
   * the phone is not paired and nothing else happens.
   */
  public fun runMacro(macro: Macro) {
    val client = actClient("macro · ${macro.label}") ?: return
    emit(TerminalLine("$", macro.command, TerminalTone.Text))
    scope.launch {
      runCatching { client.exec(execKind(macro.kind), macro.command) }
          .onSuccess { emitExec(it) }
          .onFailure { emitFailure("macro · ${macro.label}", it) }
    }
  }

  /** How a macro's kind reaches the contract's `kind` field. */
  private fun execKind(kind: MacroKind): ExecKind =
      when (kind) {
        MacroKind.Ssh -> ExecKind.Shell
        MacroKind.AppleScript -> ExecKind.AppleScript
        MacroKind.Shortcut -> ExecKind.Shortcut
      }

  public fun openMacroEditor() {
    macroEditorOpen = true
  }

  public fun closeMacroEditor() {
    macroEditorOpen = false
  }

  public fun updateMacroName(value: String) {
    macroName = value
  }

  public fun updateMacroCommand(value: String) {
    macroCommand = value
  }

  public fun updateMacroKind(value: MacroKind) {
    macroKind = value
  }

  public fun updateMacroConfirm(value: Boolean) {
    macroConfirm = value
  }

  public fun saveMacro() {
    if (macroSaveBlocked) return
    val saved =
        Macro(
            id = "u${System.currentTimeMillis()}",
            label = macroName.trim(),
            command = macroCommand.trim(),
            kind = macroKind,
            confirm = macroConfirm,
        )
    userMacros.add(0, saved)
    persistence.userMacros = userMacros.toList()
    log("ok", "macro · \"${saved.label}\" saved")
    macroEditorOpen = false
    macroName = ""
    macroCommand = ""
    macroConfirm = false
  }

  // --- controls ---------------------------------------------------------
  //
  // Each of these drives the real Mac when a Bluetooth host is connected, and
  // falls back to the mock when it is not. The local state still moves either
  // way: a keyboard is write-only, so the Mac never tells us its real volume
  // and the slider is our best guess rather than a reading. Worth remembering
  // before anyone treats these numbers as telemetry.

  public fun togglePlay() {
    playing = !playing
    sendHid(HidAction.PlayPause)
  }

  public fun previousTrack() {
    log("info", "media · previous")
    sendHid(HidAction.PreviousTrack)
  }

  public fun nextTrack() {
    log("info", "media · next")
    sendHid(HidAction.NextTrack)
  }

  /**
   * Volume up or down.
   *
   * The key press is the real mechanism and needs no pairing -- it is HID, like every other button
   * on this plate. What changed is where the NUMBER comes from: the local guess still moves so the
   * bar responds instantly, but once an agent is live the displayed percent is whatever `/v1/audio`
   * last said, and the guess is invisible. Two keys pressed on the Mac itself used to leave this
   * slider permanently wrong with no way to notice.
   */
  public fun nudgeVolume(delta: Int) {
    volume = (volume + delta).coerceIn(0, 100)
    sendHid(if (delta >= 0) HidAction.VolumeUp else HidAction.VolumeDown)
  }

  public fun nudgeBrightness(delta: Int) {
    brightness = (brightness + delta).coerceIn(0, 100)
    sendHid(if (delta >= 0) HidAction.BrightnessUp else HidAction.BrightnessDown)
  }

  /** Mission Control, Spaces and friends: the chords the esp32-s3 board already proves work. */
  public fun sendMacChord(action: HidAction) {
    sendHid(action)
    log("info", "desktop · ${desktopLabel(action)}")
  }

  /**
   * A readable name for the Console log.
   *
   * Matched on identity rather than switched on a label the UI passes in, so the log cannot drift
   * from what was actually sent.
   */
  private fun desktopLabel(action: HidAction): String =
      when (action) {
        HidAction.MissionControl -> "mission control"
        HidAction.AppExpose -> "app exposé"
        HidAction.ShowDesktop -> "show desktop"
        HidAction.Launchpad -> "launchpad"
        HidAction.SpaceLeft -> "space left"
        HidAction.SpaceRight -> "space right"
        HidAction.Spotlight -> "spotlight"
        HidAction.ScreenshotFull -> "screenshot"
        HidAction.ScreenshotRegion -> "screenshot · region"
        HidAction.ScreenshotUi -> "screenshot · capture ui"
        HidAction.CmdTab -> "switch app"
        HidAction.CycleWindows -> "cycle windows"
        HidAction.CloseWindow -> "close window"
        HidAction.MinimiseWindow -> "minimise"
        HidAction.HideApp -> "hide app"
        HidAction.Fullscreen -> "fullscreen"
        HidAction.ForceQuit -> "force quit"
        else -> "key"
      }

  private fun sendHid(action: HidAction) {
    val sender = hid ?: return
    if (!sender.send(action)) {
      // Not an error worth shouting about -- no host connected is the normal
      // state today. Logged so the Console screen shows why a press did
      // nothing, rather than leaving the user guessing.
      log("warn", "bluetooth · no host connected")
    }
  }

  /**
   * Toggles display mirroring with Cmd+F1.
   *
   * Real, and free: it is a key press, so it works with no agent and no pairing. The switch stays
   * local because HID is write-only -- macOS never tells us which way the toggle landed, so what
   * the switch shows is what we asked for, and the log says exactly what was sent.
   */
  public fun toggleMirror() {
    mirror = !mirror
    sendHid(HidAction.MirrorDisplays)
    log("info", "display · sent ⌘F1")
  }

  /**
   * Relative movement, already a delta.
   *
   * The gesture layer reports deltas, so there is nothing to subtract here. Long moves are still
   * split across reports because one report carries only -127..127 per axis.
   */
  public fun movePointerBy(dx: Float, dy: Float, buttons: Int = HidCodes.MOUSE_BUTTON_NONE) {
    var remainingX = (dx * tuning.pointerGain).roundToInt()
    var remainingY = (dy * tuning.pointerGain).roundToInt()
    if (remainingX == 0 && remainingY == 0) return
    val sender = hid ?: return
    while (remainingX != 0 || remainingY != 0) {
      val stepX = remainingX.coerceIn(-127, 127)
      val stepY = remainingY.coerceIn(-127, 127)
      sender.sendPointer(stepX, stepY, buttons)
      remainingX -= stepX
      remainingY -= stepY
    }
  }

  /** Scroll from a delta, accumulating sub-notch movement. */
  public fun scrollByDelta(dy: Float): Boolean {
    val delta = -dy / tuning.scrollDivisor + scrollRemainder
    val notches = delta.toInt()
    scrollRemainder = delta - notches
    if (notches == 0) return false
    return hid?.sendPointer(dx = 0, dy = 0, wheel = notches) ?: false
  }

  /** True while a hold-to-drag is armed, so movement carries the button down. */
  private var dragging = false

  /**
   * Presses and HOLDS the left button.
   *
   * Not a click: the button stays down until [endDrag], so the moves in between are a drag on the
   * Mac rather than a pointer move. This is the one place a button is deliberately left pressed.
   */
  public fun beginDrag(): Boolean {
    val sender = hid ?: return false
    if (!sender.sendPointer(dx = 0, dy = 0, buttons = HidCodes.MOUSE_BUTTON_LEFT)) {
      log("warn", "bluetooth · no host connected")
      return false
    }
    dragging = true
    return true
  }

  /** Movement with the button still down. */
  public fun dragBy(dx: Float, dy: Float) {
    if (!dragging) return
    movePointerBy(dx, dy, HidCodes.MOUSE_BUTTON_LEFT)
  }

  /**
   * Lifts the button.
   *
   * Runs even if the drag never armed cleanly. A button left down on the Mac turns every later
   * pointer move into a selection, and nothing in the UI would ever lift it.
   */
  public fun endDrag() {
    if (!dragging) return
    dragging = false
    hid?.sendPointer(dx = 0, dy = 0, buttons = HidCodes.MOUSE_BUTTON_NONE)
  }

  /** Returns false when nothing was sent, so the caller can skip the haptic. */
  public fun click(): Boolean = tapButton(HidCodes.MOUSE_BUTTON_LEFT)

  public fun rightClick(): Boolean = tapButton(HidCodes.MOUSE_BUTTON_RIGHT)

  /** Scrolls the Mac. Positive scrolls up, matching the wheel axis. */
  public fun scroll(amount: Int) {
    hid?.sendPointer(dx = 0, dy = 0, wheel = amount)
  }

  /**
   * Where the two-finger gesture last was, so scrolling is sent as a delta like pointer movement.
   */

  /**
   * Leftover sub-notch movement, so slow scrolling accumulates instead of rounding away to zero.
   */
  private var scrollRemainder = 0f

  /**
   * Press and release one mouse button in place.
   *
   * The release is mandatory: a button left down on the host makes the next pointer movement a
   * drag, and there is nothing in the UI that would ever lift it again.
   */
  private fun tapButton(button: Int): Boolean {
    val sender = hid ?: return false
    if (!sender.sendPointer(dx = 0, dy = 0, buttons = button)) {
      log("warn", "bluetooth · no host connected")
      return false
    }
    sender.sendPointer(dx = 0, dy = 0, buttons = HidCodes.MOUSE_BUTTON_NONE)
    return true
  }

  /** Called by the transport whenever the Bluetooth link changes. */
  public fun onHidLinkChanged(link: HidLinkState) {
    hidLink = link
  }

  public fun toggleKeyboard() {
    keyboardOpen = !keyboardOpen
  }

  public fun toggleTuning() {
    tuningOpen = !tuningOpen
  }

  /** Nudge by whole steps so the value always lands on the grid the bounds are defined on. */
  public fun nudgePointerSpeed(steps: Int) {
    updateTuning(
        tuning.copy(
            pointerPercent =
                TrackpadTuning.clampPercent(
                    tuning.pointerPercent + steps * TrackpadTuning.PERCENT_STEP)))
  }

  public fun nudgeScrollSpeed(steps: Int) {
    updateTuning(
        tuning.copy(
            scrollPercent =
                TrackpadTuning.clampPercent(
                    tuning.scrollPercent + steps * TrackpadTuning.PERCENT_STEP)))
  }

  public fun nudgeDragHold(steps: Int) {
    updateTuning(
        tuning.copy(
            dragHoldMillis =
                TrackpadTuning.clampDragHold(
                    tuning.dragHoldMillis + steps * TrackpadTuning.DRAG_HOLD_STEP_MILLIS)))
  }

  /** Back to the shipped values, for when tuning has gone somewhere unusable. */
  public fun resetTuning() {
    updateTuning(TrackpadTuning())
    log("info", "trackpad · feel reset to defaults")
  }

  private fun updateTuning(next: TrackpadTuning) {
    if (next == tuning) return
    tuning = next
    persistence.trackpadTuning = next
  }

  public fun updateAgentUrlDraft(value: String) {
    agentUrlDraft = value
  }

  /**
   * Points the app at an agent, or at none.
   *
   * Applied on a button rather than per keystroke: a URL typed one character at a time is a dozen
   * unreachable hosts in a row, and each would have logged a warning.
   */
  public fun applyAgentUrl() {
    val next = agentUrlDraft.trim()
    agentUrl = next
    persistence.agentUrl = next
    agentMetrics = null
    agentHost = null
    agentError = ""
    agentProcesses = null
    agentVms = null
    agentContainers = null
    agentK8s = null
    agentSessions = null
    agentAudio = null
    gpuWatts = null
    aneWatts = null
    powerQueryReason = ""
    if (next.isBlank()) {
      metricsSource = MetricsSource.Simulated
      log("info", "agent · none configured, dashboards simulated")
    } else {
      // Unreachable until proven otherwise: the tag must not say "live"
      // before a single byte has come back.
      metricsSource = MetricsSource.Unreachable
      log("info", "agent · ${AgentClient.normalize(next)}")
    }
  }

  /**
   * Forget the agent, and the token with it.
   *
   * Leaving the token behind would be the worst of both: a phone with no host, holding a key that
   * still opens it. The next pairing issues a fresh one anyway.
   */
  public fun forgetAgent() {
    agentUrlDraft = ""
    agentToken = ""
    persistence.agentToken = ""
    agentMac = ""
    persistence.agentMac = ""
    regeneratePairCode()
    applyAgentUrl()
  }

  private var pollsSinceHost = 0

  /**
   * One poll of the agent. Failure freezes the numbers where they are and says so; it does NOT
   * resume the simulated walk, because motion over a stale reading is the most misleading thing a
   * dashboard can do.
   */
  private var pollCount = 0

  private suspend fun pollAgent() {
    val client = AgentClient(agentUrl, agentToken)
    val result = runCatching {
      // Host identity changes never; refresh it rarely so a renamed machine
      // or an upgraded agent shows up without a restart.
      if (agentHost == null || pollsSinceHost >= HOST_REFRESH_POLLS) {
        val h = client.host()
        agentHost = h
        if (h.macAddress.isNotBlank() && h.macAddress != agentMac) {
          agentMac = h.macAddress
          persistence.agentMac = h.macAddress
        }
        pollsSinceHost = 0
      }
      pollsSinceHost++
      client.metrics()
    }
    result
        .onSuccess { m ->
          applyAgentMetrics(m)
          pollExtras(client)
          if (metricsSource != MetricsSource.Live) {
            log("ok", "agent · live from ${agentHost?.hostname ?: "host"}")
          }
          metricsSource = MetricsSource.Live
          agentError = ""
        }
        .onFailure { e ->
          val message = e.message ?: e::class.simpleName ?: "error"
          if (metricsSource == MetricsSource.Live) {
            log("warn", "agent · unreachable: $message")
          }
          metricsSource = MetricsSource.Unreachable
          agentError = message
        }
  }

  private fun applyAgentMetrics(m: AgentMetrics) {
    agentMetrics = m
    if (m.cpuReady) {
      cpu.removeAt(0)
      cpu.add(m.cpuBusyPercent.roundToInt().coerceIn(0, 100))
    }
    // The chart is scaled 0..100 and labelled Mb/s; both directions summed.
    val mbps = ((m.rxBytesPerSec + m.txBytesPerSec) * 8 / 1_000_000).roundToInt()
    net.removeAt(0)
    net.add(mbps.coerceIn(0, NET_MAX))
    powerDraw = m.drawWatts.roundToInt()
  }

  /**
   * The rest of the read surface.
   *
   * Processes and audio move every second and are asked for every tick. The four that shell out to
   * `limactl`, `docker`, `kubectl` and the filesystem cost the Mac real work for numbers that
   * change on the order of minutes, so they go every third tick -- and the PromQL power queries,
   * which leave the machine entirely, go with them.
   *
   * Each is caught on its own: one endpoint failing must not blank the other five, and it certainly
   * must not knock the whole app back to "unreachable" when `/v1/metrics` answered perfectly well.
   */
  private suspend fun pollExtras(client: AgentClient) {
    pollCount++
    runCatching { client.processes() }.onSuccess { agentProcesses = it }
    runCatching { client.audio() }.onSuccess { agentAudio = it }
    if (pollCount % SLOW_POLL_EVERY != 1) return
    runCatching { client.vms() }.onSuccess { agentVms = it }
    runCatching { client.containers() }.onSuccess { agentContainers = it }
    runCatching { client.k8s() }.onSuccess { agentK8s = it }
    runCatching { client.sessions() }.onSuccess { agentSessions = it }
    pollPower(client)
  }

  /**
   * GPU and Neural Engine power, in watts, if anything is exporting them.
   *
   * These two metrics come from `ops/macos-power-agent`, which runs `powermetrics` as root and
   * exports to Prometheus. Without that there is no way to read them at all -- which is why the
   * failure path here sets a reason the plates print, rather than leaving a stale number in place.
   */
  private suspend fun pollPower(client: AgentClient) {
    val gpuResult = runCatching { client.promql("mac_gpu_power_watts") }.getOrNull()
    if (gpuResult == null) {
      powerQueryReason = POWER_UNAVAILABLE
      gpuWatts = null
      aneWatts = null
      return
    }
    if (!gpuResult.available) {
      powerQueryReason = gpuResult.reason.ifBlank { POWER_UNAVAILABLE }
      gpuWatts = null
      aneWatts = null
      return
    }
    powerQueryReason = if (gpuResult.firstValue == null) "no series for mac_gpu_power_watts" else ""
    gpuWatts = gpuResult.firstValue
    aneWatts = runCatching { client.promql("mac_ane_power_watts") }.getOrNull()?.firstValue
  }

  public fun updateTyped(value: String) {
    typed = value
  }

  /**
   * Types the buffer on the Mac, one keystroke at a time.
   *
   * There is no "send a string" in HID -- a keyboard sends one key at a time and the host assembles
   * text -- so this walks the characters, and [HidCodes.keyFor] turns each into a press.
   *
   * Characters this layout cannot type are reported rather than dropped in silence. The alternative
   * is the Mac receiving a shorter string than the user typed with nothing to explain why, which
   * looks like data loss.
   */
  public fun sendTyped() {
    val text = typed
    typed = ""
    if (text.isEmpty()) return

    val sender = hid
    if (sender == null) {
      log("warn", "bluetooth · no host connected")
      return
    }

    val keys = mutableListOf<HidAction.Key>()
    val skipped = StringBuilder()
    for (char in text) {
      val key = HidCodes.keyFor(char)
      if (key == null) skipped.append(char) else keys.add(key)
    }

    // One sequence, not a loop of sends: the transport has to hold each key
    // down and lift it again before the next, or repeated letters vanish.
    if (!sender.sendSequence(keys)) {
      log("warn", "bluetooth · no host connected")
      return
    }

    log("ok", "keys · typed ${keys.size} character${if (keys.size == 1) "" else "s"}")
    if (skipped.isNotEmpty()) {
      // Named explicitly: "3 characters could not be typed" is useless when
      // you are trying to work out which ones.
      log("warn", "keys · not on this layout: $skipped")
    }
  }

  public fun updatePrompt(value: String) {
    prompt = value
  }

  /**
   * Relays the prompt to `claude -p` on the Mac and lands the user on that transcript.
   *
   * The "thinking…" line is a placeholder that gets REPLACED by the answer rather than followed by
   * it: leaving it above the reply would make a finished exchange look like one still in flight.
   * 180 seconds because that is the contract's ceiling for this kind, and a one-minute cut-off
   * turns most real answers into a timeout.
   */
  public fun sendPrompt() {
    val text = prompt.trim()
    if (text.isEmpty()) return
    val client = actClient("claude code · prompt") ?: return
    agentTranscript.add(TerminalLine("›", text, TerminalTone.Text))
    // Held by identity, not by index. Two prompts can be in flight at once,
    // and the first answer to land shifts every index after it -- the second
    // would then delete a line of the first one's reply.
    val placeholder = TerminalLine(" ", "thinking…", TerminalTone.Dim)
    agentTranscript.add(placeholder)
    prompt = ""
    openModule("claude")
    log("info", "claude code · prompt relayed")
    scope.launch {
      val lines =
          runCatching { client.exec(ExecKind.Claude, text, CLAUDE_TIMEOUT_S) }
              .fold(
                  onSuccess = { result ->
                    val tone = if (result.exitCode == 0) TerminalTone.Dim else TerminalTone.Err
                    val body = if (result.exitCode == 0) result.stdout else result.stderr
                    body
                        .trim()
                        .ifBlank { "claude exited ${result.exitCode} with no output" }
                        .lines()
                        .map { TerminalLine(" ", it, tone) }
                  },
                  onFailure = { listOf(TerminalLine(" ", failureText(it), TerminalTone.Err)) },
              )
      replacePlaceholder(placeholder, lines)
    }
  }

  /** Swaps the "thinking…" line for the answer, wherever it has drifted to since. */
  private fun replacePlaceholder(placeholder: TerminalLine, lines: List<TerminalLine>) {
    agentTranscript.remove(placeholder)
    agentTranscript.addAll(lines)
  }

  public fun updateCommand(value: String) {
    command = value
  }

  /** Runs the console line on the Mac through `/bin/zsh -lc`, and remembers it. */
  public fun runCommand() {
    val text = command.trim()
    if (text.isEmpty()) return
    val client = actClient("console · $text") ?: return
    emit(TerminalLine("$", text, TerminalTone.Text))
    command = ""
    remember(text)
    scope.launch {
      runCatching { client.exec(ExecKind.Shell, text) }
          .onSuccess { emitExec(it) }
          .onFailure { emitFailure("console", it) }
    }
  }

  /** Newest first, no duplicates, capped by [Persistence]. */
  private fun remember(command: String) {
    ranCommands.remove(command)
    ranCommands.add(0, command)
    while (ranCommands.size > RECENT_COMMANDS) ranCommands.removeAt(ranCommands.lastIndex)
    persistence.recentCommands = ranCommands.toList()
  }

  public fun toggleAgentPaused() {
    agentPaused = !agentPaused
  }

  /** Phone clipboard to Mac clipboard. */
  public fun pushClipboard() {
    val client = actClient("clipboard · push") ?: return
    val text = phoneClipboard?.read()
    if (text.isNullOrEmpty()) {
      log("warn", "clipboard · nothing on the phone to push")
      return
    }
    scope.launch {
      runCatching { client.setClipboard(text) }
          .onSuccess {
            clipboard = text
            log("ok", "clipboard · pushed ${text.length} characters")
          }
          .onFailure { actFailed("clipboard · push", it) }
    }
  }

  /** Mac clipboard to phone clipboard, and onto the plate that shows it. */
  public fun pullClipboard() {
    val client = actClient("clipboard · pull") ?: return
    scope.launch {
      runCatching { client.clipboard() }
          .onSuccess { text ->
            clipboard = text
            phoneClipboard?.write(text)
            log(
                if (phoneClipboard == null) "warn" else "ok",
                if (phoneClipboard == null)
                    "clipboard · pulled, but this build has no phone clipboard"
                else "clipboard · pulled ${text.length} characters",
            )
          }
          .onFailure { actFailed("clipboard · pull", it) }
    }
  }

  /** Ctrl+Cmd+Q. Distinct from Sleep: this demands a password on return, sleep does not. */
  public fun lock() {
    log("ok", "power · screen locked")
    sendHid(HidAction.LockScreen)
  }

  public fun openDialog(kind: DialogKind) {
    dialog = kind
    confirmText = ""
  }

  public fun updateConfirmText(value: String) {
    confirmText = value
  }

  public fun closeDialog() {
    dialog = null
  }

  public fun confirmDialog() {
    if (dialogBlocked) return
    when (dialog) {
      // The one power action a keyboard can actually perform. Restart and
      // Halt below stay mocked: HID cannot express them, and pretending
      // otherwise would be worse than an honest no-op.
      DialogKind.Sleep -> {
        log("info", "power · atlas sleeping")
        // Ctrl+Shift+Power on the KEYBOARD page. Consumer 0x30 -- what the
        // ESP32 sends over BLE -- is enumerated by macOS and then ignored over
        // Bluetooth Classic. Ctrl+Cmd+Q was the first workaround and does work,
        // but it LOCKS the Mac; this sleeps the display and leaves the session
        // alone, which is what was actually asked for.
        sendHid(HidAction.DisplaySleepChord)
      }
      // Real now, and the one action here that HID cannot express: a keyboard
      // has no "restart", so this is the agent or nothing.
      DialogKind.Restart -> {
        val client = actClient("power · restart")
        if (client != null) {
          log("warn", "power · restart issued")
          scope.launch {
            runCatching { client.power("restart") }.onFailure { actFailed("power · restart", it) }
          }
        }
      }
      DialogKind.Halt -> {
        agentPaused = true
        log("warn", "claude code · halted")
      }
      null -> Unit
    }
    dialog = null
  }

  public fun updatePromql(value: String) {
    promql = value
  }

  /**
   * Runs the query through the agent's Prometheus proxy.
   *
   * The panel reports what came back -- result type, how many series, the first value -- and not a
   * chart, because there is no chart here to draw one in. When no Prometheus is configured the
   * agent says so and that reason goes on screen verbatim.
   */
  public fun runPromql() {
    if (agentUrl.isBlank()) {
      promqlStatus = "no agent configured"
      return
    }
    val query = promql.trim()
    if (query.isEmpty()) return
    val client = AgentClient(agentUrl, agentToken)
    promqlStatus = "querying…"
    scope.launch {
      runCatching { client.promql(query) }
          .onSuccess { result ->
            promqlStatus =
                if (!result.available) {
                  result.reason.ifBlank { "no result, and no reason given" }
                } else {
                  val value = result.firstValue?.let { " · first ${"%.4g".format(it)}" }.orEmpty()
                  "${result.resultType.ifBlank { "result" }} · " +
                      "${result.seriesCount} series$value"
                }
            log("ok", "promql · query ran")
          }
          .onFailure {
            promqlStatus = failureText(it)
            log("warn", "promql · ${failureText(it)}")
          }
    }
  }

  /**
   * Sends a real Wake-on-LAN packet, then waits for the agent to answer.
   *
   * Broadcast twice: to the subnet-wide 255.255.255.255, and directly at the agent's own address.
   * Neither is reliable on its own -- the broadcast is what wakes a machine that has no IP yet, and
   * some networks drop it, in which case the ARP cache entry for the unicast one is what carries
   * the packet to the right switch port.
   *
   * The old version waited 1.8 seconds and declared victory. This one asks `/healthz` until it
   * answers, so "Connected" means the Mac replied and not that enough time has passed.
   */
  public suspend fun wakeHost() {
    val mac = agentMac
    if (mac.isBlank()) {
      log("warn", "power · no MAC address known, so there is nothing to wake")
      return
    }
    val packet = WakeOnLan.packetFor(mac)
    if (packet == null) {
      log("warn", "power · \"$mac\" is not a MAC address")
      return
    }
    val sent = withContext(Dispatchers.IO) { broadcast(packet) }
    if (!sent) {
      log("warn", "power · the magic packet could not be sent")
      return
    }
    log("info", "power · magic packet sent to $mac")
    if (agentUrl.isBlank()) return
    val client = AgentClient(agentUrl)
    val deadline = WAKE_TIMEOUT_MS / WAKE_PROBE_MS
    repeat(deadline.toInt()) {
      delay(WAKE_PROBE_MS)
      if (client.healthy()) {
        connection = Connection.Connected
        log("ok", "${agentHost?.hostname ?: hostShortName} · back online")
        return
      }
    }
    log("warn", "power · no answer within ${WAKE_TIMEOUT_MS / 1000} s")
  }

  /** True when at least one of the two datagrams left the phone. */
  private fun broadcast(packet: ByteArray): Boolean {
    val targets = buildList {
      add("255.255.255.255")
      if (agentUrl.isNotBlank()) add(agentHostLabel().substringBefore(':'))
    }
    var sent = false
    runCatching {
      DatagramSocket().use { socket ->
        socket.broadcast = true
        targets.forEach { target ->
          runCatching {
                val address = InetAddress.getByName(target)
                socket.send(DatagramPacket(packet, packet.size, address, WakeOnLan.PORT))
              }
              .onSuccess { sent = true }
        }
      }
    }
    return sent
  }

  public fun retryHost(): Unit = log("warn", "atlas · still unreachable")

  // --- helpers ----------------------------------------------------------

  /**
   * A client for an act endpoint, or null with the reason logged.
   *
   * The single gate every acting button goes through. Without a token the contract's act half is
   * closed to us, and the honest response is to say "not paired" once in the event stream rather
   * than to fire a request that will come back 401 and be swallowed.
   */
  private fun actClient(what: String): AgentClient? {
    if (agentUrl.isBlank()) {
      log("warn", "$what · no agent configured")
      return null
    }
    if (!paired) {
      log("warn", "$what · not paired")
      return null
    }
    return AgentClient(agentUrl, agentToken)
  }

  /**
   * One exec result, as console lines.
   *
   * The exit code is printed even when it is zero. A command that produced no output and a command
   * that failed silently look identical without it, and `exit 0` is one short line.
   */
  private fun emitExec(result: AgentExec) {
    result.stdout
        .trimEnd()
        .takeIf { it.isNotEmpty() }
        ?.lines()
        ?.forEach { emit(TerminalLine(" ", it, TerminalTone.Text)) }
    result.stderr
        .trimEnd()
        .takeIf { it.isNotEmpty() }
        ?.lines()
        ?.forEach { emit(TerminalLine(" ", it, TerminalTone.Warn)) }
    if (result.truncated) {
      emit(TerminalLine(" ", "· output truncated at 64 KiB", TerminalTone.Dim))
    }
    emit(
        TerminalLine(
            " ",
            "exit ${result.exitCode}",
            if (result.exitCode == 0) TerminalTone.Ok else TerminalTone.Err,
        ))
  }

  private fun emitFailure(what: String, error: Throwable) {
    emit(TerminalLine(" ", failureText(error), TerminalTone.Err))
    actFailed(what, error)
  }

  /**
   * One act failed. Logs it, and throws the token away if that is what went wrong.
   *
   * Keeping a rejected token would wedge the app permanently: [paired] would stay true, so the
   * pairing loop would never run again, and every button would keep failing with a 403 that nothing
   * could clear short of Forget. Dropping it puts the code back on screen and the loop back to
   * work.
   */
  private fun actFailed(what: String, error: Throwable) {
    if (error is AgentAuthException && paired) {
      agentToken = ""
      persistence.agentToken = ""
      regeneratePairCode()
      log("warn", "$what · token rejected, pair again with the new code")
      return
    }
    log("warn", "$what · ${failureText(error)}")
  }

  /** An auth failure has a remedy and says so; everything else is the Mac not answering. */
  private fun failureText(error: Throwable): String =
      if (error is AgentAuthException) "not paired"
      else error.message ?: error::class.simpleName ?: "error"

  private fun emit(vararg lines: TerminalLine) {
    terminal.addAll(lines)
    while (terminal.size > TERMINAL_LIMIT) {
      terminal.removeAt(0)
    }
  }

  private fun log(level: String, message: String) {
    logs.add(0, LogEntry(Clock.now(), level, message))
    while (logs.size > LOG_LIMIT) {
      logs.removeAt(logs.lastIndex)
    }
  }

  /** `1.9 GB`, `612 MB`. The unit the number deserves, not always the same one. */
  private fun formatBytes(bytes: Long): String =
      when {
        bytes >= GIB -> "${"%.1f".format(bytes / GIB)} GB"
        bytes >= MIB -> "${(bytes / MIB).roundToInt()} MB"
        else -> "${(bytes / 1024.0).roundToInt()} KB"
      }

  private fun plural(count: Int): String = if (count == 1) "" else "s"

  private companion object {
    const val POINTER_HINT = "drag · tap · 2-finger scroll · hold to drag · 3-finger swipe"

    const val PAIR_TTL_MS = 5 * 60 * 1000L
    const val PAIR_CODE_BOUND = 1_000_000
    const val CLAUDE_TIMEOUT_S = 180
    const val RECENT_COMMANDS = 20
    const val SLOW_POLL_EVERY = 3
    const val MIB = 1024.0 * 1024.0

    /** The floor on the Hosts screen's refresh setting - a second is a second. */
    const val MIN_POLL_MS = 1000L
    const val WAKE_TIMEOUT_MS = 60_000L
    const val WAKE_PROBE_MS = 2000L
    const val POWER_UNAVAILABLE = "n/a · needs powermetrics (root) or Prometheus"

    /** Six digits, split for reading aloud. The wire form strips the space back out. */
    fun formatPairCode(value: Int): String {
      val digits = value.toString().padStart(6, '0')
      return "${digits.take(3)} ${digits.drop(3)}"
    }

    const val HOST_REFRESH_POLLS = 40
    const val GIB = 1024.0 * 1024.0 * 1024.0
    const val SECONDS_PER_DAY = 86_400L
    const val BATTERY_WARN_PERCENT = 20
    const val MEMORY_SEGMENTS = 16

    /** Where the bar turns amber. Above this the machine is swapping soon. */
    const val MEMORY_WARN_PERCENT = 75
    const val DOWN_FACTOR = 1.2
    const val UP_FACTOR = 0.3
    const val CPU_STEP = 16
    const val CPU_MIN = 6
    const val CPU_MAX = 96
    const val NET_STEP = 30
    const val NET_MIN = 4
    const val NET_MAX = 100
    const val GPU_STEP = 8
    const val GPU_MIN = 4
    const val GPU_MAX = 98
    const val ANE_STEP = 6
    const val ANE_MAX = 90
    const val TEMP_STEP = 2
    const val TEMP_MIN = 38
    const val TEMP_MAX = 92
    const val FAN_BASE = 900
    const val FAN_PER_DEGREE = 14
    const val DRAW_BASE = 12
    const val DRAW_DIVISOR = 3
  }
}

/** The copy and behaviour of one confirmation dialog. */
public data class DialogSpec(
    val kicker: String,
    val destructive: Boolean,
    val title: String,
    val body: String,
    val action: String,
    val word: String?,
) {
  public companion object {
    /**
     * Builds the dialog's copy.
     *
     * The typed confirmation is skipped entirely when the Hosts switch is off, which is why
     * [confirmDestructive] reaches in here rather than being checked at the call site.
     */
    public fun of(kind: DialogKind, wakeOnLan: Boolean, confirmDestructive: Boolean): DialogSpec =
        when (kind) {
          DialogKind.Sleep ->
              DialogSpec(
                  kicker = "Power",
                  destructive = false,
                  title = "Sleep atlas?",
                  body =
                      "Displays off, SSH session kept alive by Tailscale. " +
                          "Wake on LAN is ${if (wakeOnLan) "on" else "off"}.",
                  action = "Sleep",
                  word = null,
              )
          DialogKind.Restart ->
              DialogSpec(
                  kicker = "Destructive · power",
                  destructive = true,
                  title = "Restart atlas?",
                  body =
                      "2 Claude Code sessions and 2 Lima VMs will be interrupted. " +
                          "Homelab control plane loses one node until reboot completes.",
                  action = "Restart",
                  word = "restart".takeIf { confirmDestructive },
              )
          DialogKind.Halt ->
              DialogSpec(
                  kicker = "Destructive · agent",
                  destructive = true,
                  title = "Halt Claude Code?",
                  body =
                      "Kills the running CLI process. Uncommitted edits in " +
                          "worktree/auth stay on disk.",
                  action = "Halt",
                  word = "halt".takeIf { confirmDestructive },
              )
        }
  }
}
