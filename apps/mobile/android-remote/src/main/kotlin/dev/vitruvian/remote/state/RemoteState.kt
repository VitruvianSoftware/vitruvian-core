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
     * The phone's own notification shade, as a port for the same reason as [phoneClipboard]: this
     * class has no `Context` and must not acquire one.
     *
     * Null in previews and tests, and then nothing is posted -- which is correct, because a
     * notification is a claim that something happened while nobody was looking, and a test is
     * always looking.
     */
    private val notifier: Notifier? = null,
    /**
     * The phone bridge -- the foreground service, the trust window and the permission dialogs.
     *
     * A port for the same reason as [notifier]: all three of those need a `Context` and this class
     * has none. Null in previews and tests, and the Hosts plate then says the bridge is unavailable
     * instead of drawing a switch that cannot start anything.
     */
    private val bridge: BridgeControl? = null,
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

  /**
   * Every Mac this phone knows, and which one it is talking to.
   *
   * A list rather than one host because the token is per-Mac: switching by retyping a URL would
   * throw away the pairing every time, which made a second Mac cost more than it was worth.
   */
  public var hosts: List<AgentHostEntry> by mutableStateOf(persistence.hosts)
    private set

  public var selectedHostId: String by
      mutableStateOf(
          persistence.selectedHostId.ifBlank { persistence.hosts.firstOrNull()?.id.orEmpty() })
    private set

  /** The Mac every call below goes to. Null means there is none and the app is simulating. */
  public val selectedHost: AgentHostEntry?
    get() = hosts.firstOrNull { it.id == selectedHostId } ?: hosts.firstOrNull()

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

  /** Where the selected agent is; blank means none and the dashboards stay simulated. */
  public val agentUrl: String
    get() = selectedHost?.url.orEmpty()

  /** What the user is typing on the Hosts screen; applied by [applyAgentUrl], not per keystroke. */
  // Shown as what will be dialled, not as typed: a stray space the keyboard
  // inserted would otherwise sit in the field looking like a tolerated typo.
  public var agentUrlDraft: String by
      mutableStateOf(
          persistence.hosts.firstOrNull()?.url.orEmpty().let {
            if (it.isBlank()) it else AgentClient.normalize(it).substringAfter("://")
          })
    private set

  /** The selected host's name, edited on the same plate as its address. */
  public var hostAliasDraft: String by
      mutableStateOf(persistence.hosts.firstOrNull()?.alias.orEmpty())
    private set

  /** The address typed into the "Add a Mac" row. Separate so it cannot overwrite the one above. */
  public var newHostDraft: String by mutableStateOf("")
    private set

  public var metricsSource: MetricsSource by
      mutableStateOf(
          if (persistence.hosts.isEmpty()) MetricsSource.Simulated else MetricsSource.Unreachable)
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
  public val agentToken: String
    get() = selectedHost?.token.orEmpty()

  public val paired: Boolean
    get() = agentToken.isNotBlank()

  /** [pairCode] as the Mac's `pair` subcommand wants it: six digits, no space. */
  public val pairDigits: String
    get() = pairCode.filterNot { it.isWhitespace() }

  /** en0's address, kept because a sleeping Mac cannot be asked for it. */
  public val agentMac: String
    get() = selectedHost?.mac.orEmpty()

  // Each of the contract's read endpoints, exactly as it answered. Null means
  // "not asked yet"; an AgentList that says available:false carries the Mac's
  // own reason, and the screens print that instead of an empty list.
  public var agentProcesses: List<AgentProcess>? by mutableStateOf(null)
    private set

  public var agentOllama: AgentOllama? by mutableStateOf(null)
    private set

  public var agentTools: AgentTools? by mutableStateOf(null)
    private set

  public var agentAntigravity: AgentAntigravity? by mutableStateOf(null)
    private set

  /** The last PromQL reply, for the Grafana-panel module. */
  public var promqlResult: AgentPromql? by mutableStateOf(null)
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

  // The v1.2 read surface.
  public var agentClaudeSessions: List<AgentClaudeSession>? by mutableStateOf(null)
    private set

  public var agentPrs: AgentList<AgentPr>? by mutableStateOf(null)
    private set

  public var agentArgo: AgentList<AgentArgoApp>? by mutableStateOf(null)
    private set

  /**
   * Whether the agent has anywhere to publish notifications. Null until `/healthz` has answered.
   */
  public var agentNotify: AgentNotifyStatus? by mutableStateOf(null)
    private set

  // --- the phone bridge -------------------------------------------------

  /** Whether the bridge service should be running. Off until someone turns it on. */
  public var bridgeEnabled: Boolean by mutableStateOf(persistence.bridgeEnabled)
    private set

  /** Whether the outbound link to the Mac agent is up right now. */
  public var bridgeLinked: Boolean by mutableStateOf(false)
    private set

  /**
   * What the link is doing when it is not up: "connecting…", "not paired", the socket's own error.
   *
   * Shown verbatim on the plate, because "not linked" with no reason is the state nobody can fix.
   */
  public var bridgeLinkStatus: String by mutableStateOf("off")
    private set

  /** When the trust window shuts, epoch millis; 0 means it was never opened. */
  public var trustUntil: Long by mutableStateOf(0L)
    private set

  /** The outbound call waiting for an answer, if any. */
  public var pendingApproval: BridgePending? by mutableStateOf(null)
    private set

  /** The last [BridgePolicy.AUDIT_LIMIT] tool calls, newest first. */
  public var bridgeAudit: List<BridgeAuditEntry> by mutableStateOf(emptyList())
    private set

  /** Every permission the bridge's tools need, with its state. Refreshed when the screen shows. */
  public var bridgePermissions: List<BridgePermissionState> by mutableStateOf(emptyList())
    private set

  /**
   * The clock the trust countdown is read against.
   *
   * Held as state and advanced by the tick rather than read from `System` inside the getter: a
   * value Compose cannot observe would leave "59 min left" on screen until something unrelated
   * caused a recomposition, which is the same failure as a stopped clock.
   */
  public var bridgeNowMs: Long by mutableStateOf(System.currentTimeMillis())
    private set

  /**
   * Which session a supplemental instruction would be resumed into.
   *
   * Null means none picked, and Send then falls back to a NEW `claude -p` run rather than guessing
   * a session -- sending an instruction into someone else's half-finished conversation because it
   * happened to be first in the list is the failure worth avoiding here.
   */
  public var selectedSessionId: String? by mutableStateOf(null)
    private set

  // --- screen peek ------------------------------------------------------
  //
  // Every capture is a tap. There is no timer here on purpose: a remote that
  // silently re-screenshots someone's Mac once a second is a different piece
  // of software from one that shows a still when asked.

  public var peekOpen: Boolean by mutableStateOf(false)
    private set

  /** The last JPEG the Mac sent, undecoded. Null until one arrives. */
  public var peekImage: ByteArray? by mutableStateOf(null)
    private set

  public var peekLoading: Boolean by mutableStateOf(false)
    private set

  /**
   * Why there is no picture, in the Mac's own words.
   *
   * Almost always "Screen Recording is not granted to the agent" plus the exact path through System
   * Settings -- which is the entire value of the field: no network error message would tell anyone
   * how to fix it, and a blank plate would tell them nothing at all.
   */
  public var peekReason: String by mutableStateOf("")
    private set

  /**
   * The part of the display the plate is showing. [Derive.PeekRegion.Full] until a pinch; the agent
   * crops the native capture to it, which is what makes zoom show detail instead of blur.
   */
  public var peekRegion: Derive.PeekRegion by mutableStateOf(Derive.PeekRegion.Full)
    private set

  /**
   * Whether a streamed command is in flight, and what it is.
   *
   * The pair the Stop button hangs off. Without it a four-minute build and a command that died
   * instantly look identical: output stops in both cases, and only one of them is still running.
   */
  public var commandRunning: Boolean by mutableStateOf(false)
    private set

  public var runningLabel: String by mutableStateOf("")
    private set

  /** The open connection, so Stop can close it. Closing IS the cancellation. */
  private var runningHandle: ExecStreamHandle? = null

  /**
   * Whether the activity is on screen.
   *
   * Only used to decide whether a finished command deserves a notification: telling someone who is
   * watching the output that the output has arrived is noise.
   */
  private var foreground: Boolean = true

  /**
   * GPU and Neural Engine power, in watts, from `tools/ops/macos-power-agent` via Prometheus.
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

  // Seeded with the canned demo ONLY while no agent is configured. With a
  // real Mac behind the console, a transcript that opens on a conversation
  // nobody had and a terminal showing commands nobody ran is the exact kind
  // of pretending the LIVE tag promises not to do.
  private val demo: Boolean = persistence.hosts.isEmpty()

  public val terminal: SnapshotStateList<TerminalLine> =
      (if (demo) MockHost.initialTerminal else emptyList()).toMutableStateList()
  public val agentTranscript: SnapshotStateList<TerminalLine> =
      (if (demo) MockHost.initialAgentTranscript else emptyList()).toMutableStateList()
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
    get() =
        when {
          ranCommands.isNotEmpty() -> ranCommands.toList()
          // Canned examples only in simulated mode: on a real Mac a chip
          // labelled "recent" would run a command nobody here ever ran.
          agentUrl.isBlank() -> MockHost.recentCommands
          else -> emptyList()
        }

  // Same rule as the terminal: the demo event stream only when there is no
  // real Mac to produce one.
  public val logs: SnapshotStateList<LogEntry> =
      (if (demo)
              listOf(
                  LogEntry("04:37:02", "ok", "homelab · 3/3 nodes ready, no drift"),
                  LogEntry("04:36:51", "warn", "lima · k8s-node-3 stopped (manual)"),
                  LogEntry("04:36:44", "info", "claude code · session 2 resumed"),
                  LogEntry("04:35:10", "ok", "antigravity · build #412 green"),
                  LogEntry("04:31:00", "info", "atlas · connected via tailscale (4 ms)"),
              )
          else emptyList())
          .toMutableStateList()

  // --- clipboard and power ---------------------------------------------
  public var clipboard: String by
      mutableStateOf("https://github.com/VitruvianSoftware/vitruvian-core/pull/1551")
    private set

  public var dialog: DialogKind? by mutableStateOf(null)
    private set

  public var confirmText: String by mutableStateOf("")
    private set

  // --- PromQL panel -----------------------------------------------------
  // This Mac's own power series: a handful of results, and the metric the
  // dashboards already depend on. The old default matched every CPU on
  // every node in the lab and came back larger than the proxy allows.
  public var promql: String by mutableStateOf("mac_soc_power_watts")
    private set

  public var promqlStatus: String by mutableStateOf("Run a query to fill this panel")
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

  /**
   * The Hosts list, one row per saved Mac.
   *
   * The mock pair is shown only while nothing real is saved -- that is the app with no Mac yet, and
   * it is the one case where a simulated host is honest. The moment a real one exists, `forge`
   * disappears entirely rather than sitting under it looking like a second machine that is asleep.
   *
   * Only the SELECTED host is polled, so only it can claim live or unreachable. The others say
   * "saved", which is all this phone actually knows about them.
   */
  public val hostRows: List<Host>
    get() =
        when {
          isUnpaired -> emptyList()
          hosts.isEmpty() -> MockHost.hosts
          else -> hosts.map(::hostRow)
        }

  private fun hostRow(entry: AgentHostEntry): Host {
    val current = entry.id == selectedHost?.id
    val live = agentHost.takeIf { current }
    val address = AgentClient.normalize(entry.url).substringAfter("://")
    return Host(
        id = entry.id,
        name =
            if (live != null) "${entry.alias} · ${live.chip}" else entry.alias.ifBlank { address },
        subtitle =
            if (live != null)
                "$address · macOS ${live.osVersion} · ${Format.memoryBytes(live.memoryBytes)}"
            else address,
        tone =
            when {
              !current -> StatusTone.Neutral
              metricsSource == MetricsSource.Live -> StatusTone.Ok
              else -> StatusTone.Crit
            },
        tag = if (current) metricsSource.label else "saved",
        tagTone =
            when {
              !current -> TagTone.Outline
              metricsSource == MetricsSource.Live -> TagTone.Ok
              else -> TagTone.Sanguine
            },
    )
  }

  /** The short name the top bar and rail show - `atlas`, not the full row title. */
  public val hostShortName: String
    get() =
        when {
          isUnpaired -> "no host"
          // No Mac saved: the app is simulating, and the mock's own name is
          // what every other simulated figure on screen belongs to.
          hosts.isEmpty() -> MockHost.hosts.first().name.substringBefore(" · ")
          else -> selectedHost?.alias?.ifBlank { null } ?: agentHost?.hostname ?: "no host"
        }

  /**
   * The alias, or the Mac's hostname cut down to something readable.
   *
   * `James-MacBook-Pro.local` becomes `james-macbook-pro`: the domain says nothing a chip has room
   * for, and the capitals are Apple's, not the user's. Blank when no agent has answered yet, which
   * is what sends [hostShortName] to the host list for a name.
   */
  private fun shortHostName(): String =
      when {
        !selectedHost?.alias.isNullOrBlank() -> selectedHost?.alias.orEmpty()
        else -> agentHost?.hostname?.let(Format::shortHost).orEmpty()
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
            memory = Format.memoryBytes(it.memoryBytes),
        )
      }
    }

  public val processesNotice: Notice?
    get() =
        if (isLive && agentProcesses == null)
            Notice("Sampling…", "the agent is taking its first reading")
        else null

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
                Format.parts(
                    vm.arch, "${vm.cpus} cpu", Format.memoryBytes(vm.memoryBytes), vm.vmType),
            tone = if (running) StatusTone.Ok else StatusTone.Warn,
            tag = vm.status.lowercase(Locale.ROOT),
            tagTone = if (running) TagTone.Ok else TagTone.Warn,
        )
      }
    }

  public val vmsNotice: Notice?
    get() = liveNotice(agentVms, "limactl") { "Lima VMs unavailable" }

  public val containers: List<Container>
    get() {
      val live = agentContainers
      if (!isLive || live == null || !live.available) {
        return if (isLive) emptyList() else MockHost.containers
      }
      return live.items.map { Container(it.name, it.image, it.status) }
    }

  public val containersNotice: Notice?
    get() = liveNotice(agentContainers, "docker / podman", Format::containerTitle)

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

  public val nodesNotice: Notice?
    get() =
        if (!isLive) Notice("No cluster behind this screen", "simulated")
        else liveNotice(agentK8s, "kubectl") { "K3s nodes unavailable" }

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
        watts != null -> HonestMetric(label, Format.watts(watts), "power, not load", null)
        else -> HonestMetric(label, "n/a", powerQueryReason.ifBlank { POWER_UNAVAILABLE }, null)
      }

  /**
   * Thermals on the Mac screen, mirroring the Home widget rather than contradicting it.
   *
   * Two tiles claiming different temperatures for one machine is worse than one tile saying it
   * cannot read the SoC, which is the truth: there is no die temperature and no fan speed without
   * root, so this reports throttling state and the battery's own sensor.
   *
   * What it no longer does is say so HERE. Five plates each carrying their own "n/a" turned the
   * screen into a list of apologies; [computeFootnote] says it once, at the bottom, and every plate
   * above it just shows what it has.
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
          sub = "battery ${m.batteryTemperatureC.roundToInt()}°",
          percent = if (m.throttled) 100 - m.cpuSpeedLimitPercent else null,
          warn = m.throttled,
      )
    }

  /**
   * The line under the CPU spark.
   *
   * `top` reports one busy figure for the machine, not a P/E split -- that needs `powermetrics` and
   * root. The line said "P-cores 34% · E-cores 12%" for numbers nothing had ever measured, and then
   * said "P/E split n/a", which was true but is [computeFootnote]'s job. What it carries now is
   * what this Mac actually reports: the load average and how many cores are sharing it.
   */
  public val cpuBreakdown: String
    get() {
      if (!isLive) return "P-cores 34% · E-cores 12%"
      val m = agentMetrics ?: return "sampling…"
      val cores = agentHost?.cores?.takeIf { it > 0 }?.let { "$it cores" }
      return Format.parts("load ${"%.2f".format(m.load1)}", cores)
    }

  /**
   * The one place the Mac screen admits what it cannot read.
   *
   * Every figure named here needs root (`powermetrics`), an SMC reader, or a second sampling call
   * the agent does not make. Each used to be an "n/a" on the plate it belonged to; five of those
   * across one screen read as a broken app rather than an honest one, and the honesty was harder to
   * find, not easier. Null when nothing is being measured at all -- the simulated screen has a
   * bigger caveat than this one, and it is already tagged.
   */
  public val computeFootnote: String?
    get() =
        if (!isLive) null
        else
            "Not readable without root: SoC temperature, fans, P/E split, swap, " +
                "disk throughput."

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
              Format.parts(
                  Format.memoryPair(m.memoryUsedBytes, m.memoryTotalBytes),
                  "kernel free ${m.memoryFreePercent}%",
              ),
          percent = pressure,
      )
    }

  /**
   * app / wired / compressed / cached, which `vm_stat` gives and this agent does not read.
   *
   * Empty while live rather than one line saying so: that sentence was the fourth "not read" on the
   * screen, and it now lives once in [computeFootnote].
   */
  public val memoryBreakdown: List<String>
    get() =
        if (isLive) emptyList()
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
          // `df` gives both halves, and both are worth more than the word
          // "used" on its own: the percent says how full, these say how much
          // room is left, which is the question anyone actually has.
          sub =
              Format.parts(
                  m.diskUsedBytes.takeIf { it > 0 }?.let { "${Format.formatBytes(it)} used" },
                  m.diskAvailableBytes.takeIf { it > 0 }?.let { "${Format.formatBytes(it)} free" },
              ),
          percent = used,
      )
    }

  /** What the console is actually talking to. */
  public val consoleSubtitle: String
    get() =
        when {
          agentUrl.isBlank() -> "zsh · no agent configured"
          else -> Format.parts("zsh -lc", hostShortName, "via the agent")
        }

  /** Where a PromQL query would go, named rather than asserted. */
  public val promqlSource: String
    get() =
        when {
          agentUrl.isBlank() -> "source · none · configure the agent on Hosts"
          else -> "source · ${agentHostLabel()} · via the Mac agent"
        }

  /** The Mac screen's header line. */
  public val computeSubline: String
    get() {
      val h = agentHost ?: return "Apple M4 Max · 16c CPU · 40c GPU · 64 GB"
      return Format.parts(h.model, h.chip, "${h.cores} cores", Format.memoryBytes(h.memoryBytes))
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

  /**
   * A list's absence, as a headline and the tool's own words.
   *
   * The title comes from [headline], which is given the reason: Docker's socket error has a
   * recognisable shape worth naming, most tools' do not. The raw reason goes underneath, clipped to
   * one line -- nothing is hidden, it is just no longer the headline.
   */
  private fun <T> liveNotice(
      list: AgentList<T>?,
      tool: String,
      headline: (String) -> String,
  ): Notice? =
      when {
        !isLive -> null
        list == null -> Notice("Asking $tool…", "")
        !list.available -> {
          val reason = list.reason.ifBlank { "$tool said nothing about why" }
          Notice(headline(reason), Format.clip(reason))
        }
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
    val pressure = (100 - m.memoryFreePercent).coerceIn(0, 100)
    val cpuValue = if (m.cpuReady) "${m.cpuBusyPercent.roundToInt()}%" else "…"
    val cpuSub =
        when {
          !m.cpuReady -> "sampling…"
          h != null -> "${h.chip} · ${h.cores} cores"
          else -> "load ${"%.2f".format(m.load1)}"
        }
    val thermalValue = if (m.throttled) "${m.cpuSpeedLimitPercent}%" else "ok"
    val thermalSub = "battery ${m.batteryTemperatureC.roundToInt()}°"
    val batValue = if (m.batteryPresent) "${m.batteryPercent}%" else "n/a"
    val batSub =
        when {
          !m.batteryPresent -> "no battery"
          m.charging -> "$powerDraw W · charging"
          m.onAc -> "on AC"
          else -> "$powerDraw W · on battery"
        }
    return listOf(
        Widget(
            "cpu", "CPU", cpuValue, cpuSub, if (m.cpuReady) m.cpuBusyPercent.roundToInt() else 0),
        Widget(
            "mem",
            "Memory pressure",
            "$pressure%",
            "${Format.memoryPair(m.memoryUsedBytes, m.memoryTotalBytes)} used",
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
      agentClaudeSessions?.let { sessions ->
        val waiting = sessions.count { Derive.claudeWaiting(it.state) }
        val idle = sessions.isEmpty()
        rows +=
            RunningItem(
                moduleId = "claude",
                title = "Claude Code",
                // "2 sessions · 1 waiting" -- the second half is the reason
                // to look, and it is missing when nothing is waiting rather
                // than printed as a zero.
                subtitle =
                    Format.parts(
                        "${sessions.size} session${plural(sessions.size)}",
                        if (waiting > 0) "$waiting waiting" else null,
                    ),
                tone =
                    when {
                      waiting > 0 -> StatusTone.Warn
                      idle -> StatusTone.Neutral
                      else -> StatusTone.Run
                    },
                tag =
                    when {
                      waiting > 0 -> "waiting"
                      idle -> "idle"
                      else -> "running"
                    },
                tagTone =
                    when {
                      waiting > 0 -> TagTone.Warn
                      idle -> TagTone.Neutral
                      else -> TagTone.Accent
                    },
            )
      }
      agentPrs?.let { list ->
        val states =
            list.items.map {
              Derive.prCheck(it.isDraft, it.checksSuccess, it.checksFailure, it.checksPending)
            }
        val green = states.count { it == Derive.PrCheck.Green }
        val red = states.count { it == Derive.PrCheck.Red }
        rows +=
            RunningItem(
                moduleId = "prs",
                title = "Pull requests",
                subtitle =
                    if (list.available) "${list.items.size} open · $green green · $red red"
                    // gh missing, or logged out, in gh's own words.
                    else Format.clip(list.reason.ifBlank { "gh said nothing about why" }),
                tone =
                    when {
                      !list.available -> StatusTone.Neutral
                      red > 0 -> StatusTone.Crit
                      else -> StatusTone.Ok
                    },
                tag =
                    when {
                      !list.available -> "no source"
                      red > 0 -> "$red red"
                      else -> "${list.items.size} open"
                    },
                tagTone =
                    when {
                      !list.available -> TagTone.Outline
                      red > 0 -> TagTone.Sanguine
                      else -> TagTone.Ok
                    },
            )
      }
      agentAntigravity?.let { ag ->
        rows +=
            RunningItem(
                moduleId = "antigravity",
                title = "Antigravity",
                subtitle =
                    if (ag.available) "v${ag.version} · ${ag.models.size} models" else ag.reason,
                tone = if (ag.available) StatusTone.Ok else StatusTone.Neutral,
                tag = if (ag.available) "ready" else "no source",
                tagTone = if (ag.available) TagTone.Ok else TagTone.Outline,
            )
      }
      agentOllama?.let { o ->
        val loaded = o.running.size
        rows +=
            RunningItem(
                moduleId = "ollama",
                title = "Ollama",
                subtitle =
                    if (o.available) "${o.models.size} models · $loaded loaded" else o.reason,
                tone = if (!o.available) StatusTone.Neutral else StatusTone.Ok,
                tag =
                    when {
                      !o.available -> "no source"
                      loaded > 0 -> "$loaded loaded"
                      else -> "idle"
                    },
                tagTone =
                    when {
                      !o.available -> TagTone.Outline
                      loaded > 0 -> TagTone.Ok
                      else -> TagTone.Neutral
                    },
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
        val outOfSync =
            agentArgo?.takeIf { it.available }?.items?.count { !Derive.argoOk(it.sync, it.health) }
        rows +=
            RunningItem(
                moduleId = "homelab",
                title = "Homelab · K3s",
                subtitle =
                    if (k.available)
                        Format.parts(
                            "$ready/${k.items.size} nodes ready",
                            k.detail.ifBlank { null },
                            // ArgoCD as a clause on the row that already
                            // exists rather than a second cluster row: it is
                            // the same cluster, and two rows for it would
                            // read as two of them.
                            when {
                              outOfSync == null -> null
                              outOfSync > 0 -> "$outOfSync out of sync"
                              else ->
                                  "${agentArgo?.items?.size ?: 0} app" +
                                      "${plural(agentArgo?.items?.size ?: 0)} synced"
                            },
                        )
                    else k.reason,
                tone =
                    when {
                      !k.available -> StatusTone.Neutral
                      (outOfSync ?: 0) > 0 -> StatusTone.Warn
                      ready == k.items.size && ready > 0 -> StatusTone.Ok
                      else -> StatusTone.Warn
                    },
                tag =
                    when {
                      !k.available -> "no source"
                      (outOfSync ?: 0) > 0 -> "$outOfSync drifted"
                      else -> "$ready/${k.items.size}"
                    },
                tagTone =
                    when {
                      !k.available -> TagTone.Outline
                      (outOfSync ?: 0) > 0 -> TagTone.Warn
                      ready == k.items.size && ready > 0 -> TagTone.Ok
                      else -> TagTone.Warn
                    },
            )
      }
      agentContainers?.let { c ->
        rows +=
            RunningItem(
                moduleId = "docker",
                title =
                    if (c.available)
                        c.detail.ifBlank { "Containers" }.replaceFirstChar { it.uppercase() }
                    else Format.containerTitle(c.reason),
                subtitle =
                    if (c.available) "${c.items.size} container${plural(c.items.size)}"
                    // The runtime's own sentence, cut to one line: the full
                    // Docker socket error is three times the width of a row.
                    else Format.clip(c.reason),
                tone = if (c.available) StatusTone.Ok else StatusTone.Neutral,
                tag = if (c.available) "${c.items.size}" else "no source",
                tagTone = if (c.available) TagTone.Ok else TagTone.Outline,
            )
      }
      return rows
    }

  public val moduleDashboards: Map<String, ModuleDashboard>
    get() {
      // MockHost has no pull-request mock and should not grow one: the module
      // is about YOUR open PRs, and invented ones would be indistinguishable
      // from real ones on the same plate.
      val mocked =
          MockHost.dashboards(agentTranscript.toList(), !agentPaused) +
              ("prs" to simulatedPrsDashboard())
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
        "prs" -> prsDashboard()
        "lima" -> limaDashboard()
        "homelab" -> homelabDashboard()
        "docker" -> dockerDashboard()
        "ollama" -> ollamaDashboard()
        "antigravity" -> antigravityDashboard()
        "grafana" -> grafanaDashboard()
        else -> null
      }

  /** The sessions the agent inferred, newest state first-hand rather than the phone's guess. */
  private fun claudeDashboard(): ModuleDashboard {
    val sessions = agentClaudeSessions.orEmpty()
    val processes = agentSessions?.runningProcesses ?: 0
    val waiting = sessions.count { Derive.claudeWaiting(it.state) }
    val selected = selectedSession
    return ModuleDashboard(
        id = "claude",
        name = "Claude Code",
        meta = Format.parts("~/.claude/projects", shortHostName().ifBlank { "host" }),
        status =
            when {
              waiting > 0 -> "$waiting waiting"
              processes > 0 -> "running"
              else -> "idle"
            },
        statusTone =
            when {
              waiting > 0 -> StatusTone.Warn
              processes > 0 -> StatusTone.Run
              else -> StatusTone.Neutral
            },
        metrics =
            listOf(
                ModuleMetric("Sessions", "${sessions.size}", "in ~/.claude/projects"),
                // The tile that earns the module: a session blocked on a
                // permission prompt is one nobody is watching, and it is the
                // only number here that asks the user to do something.
                ModuleMetric("Waiting", "$waiting", "for permission"),
                ModuleMetric("Processes", "$processes", "claude processes"),
            ),
        streamLabel =
            if (selected != null) "Session · ${sessionName(selected)}"
            else "Transcript · this phone",
        lines = transcriptLines(selected),
        cursor = !agentPaused,
        prompts = true,
        listLabel = "Sessions",
        rows = sessions.map(::claudeSessionRow),
    )
  }

  /** The selected session, or null when nothing is selected or the selection has gone away. */
  private val selectedSession: AgentClaudeSession?
    get() = agentClaudeSessions?.firstOrNull { it.sessionId == selectedSessionId }

  /**
   * What the stream pane shows.
   *
   * With a session selected: what that session last said, from the Mac, above this phone's own
   * exchanges with it. The two are labelled separately because they came from different places --
   * the first is the transcript on the Mac, the rest is what was typed here.
   */
  private fun transcriptLines(session: AgentClaudeSession?): List<TerminalLine> {
    if (session == null) return agentTranscript.toList()
    val head = mutableListOf<TerminalLine>()
    head += TerminalLine(" ", "last from ${sessionName(session)}", TerminalTone.Dim)
    when {
      session.lastText.isNotBlank() ->
          head += TerminalLine("‹", session.lastText, TerminalTone.Text)
      session.lastTool.isNotBlank() ->
          head += TerminalLine("‹", "tool · ${session.lastTool}", TerminalTone.Dim)
      else -> head += TerminalLine("‹", "nothing parseable in the last records", TerminalTone.Dim)
    }
    return head + agentTranscript.toList()
  }

  /**
   * One Claude Code session as a row.
   *
   * The home directory is INFERRED rather than assumed: the agent's session path runs through
   * `~/.claude/projects`, so everything before that is the home directory on the machine that
   * answered -- no `/Users/<name>` guess, which is wrong the moment the Mac has two accounts.
   */
  private fun claudeSessionRow(session: AgentClaudeSession): ModuleRow {
    val waiting = Derive.claudeWaiting(session.state)
    val state = Derive.claudeStateLabel(session.state)
    return ModuleRow(
        title = sessionName(session),
        // What it is doing, in its own words. A path here would repeat the
        // title; the last thing it said is the only thing that distinguishes
        // two sessions in the same repository.
        subtitle =
            when {
              session.lastText.isNotBlank() -> Format.clip(session.lastText)
              session.lastTool.isNotBlank() -> "tool · ${session.lastTool}"
              else -> session.cwd.ifBlank { session.project }
            },
        // The raw timestamp survives only when it cannot be read as a time;
        // an unparseable date shown as "just now" would be an invention.
        trailing =
            Format.relativeTime(session.lastActive, System.currentTimeMillis()).ifBlank {
              session.lastActive
            },
        tone =
            when {
              waiting -> StatusTone.Warn
              state == "working" -> StatusTone.Run
              state == "idle" -> StatusTone.Ok
              else -> StatusTone.Neutral
            },
        tag = state,
        tagTone =
            when {
              waiting -> TagTone.Warn
              state == "working" -> TagTone.Accent
              state == "idle" -> TagTone.Neutral
              else -> TagTone.Outline
            },
        selected = session.sessionId == selectedSessionId,
        onSelect = { selectSession(session.sessionId) },
    )
  }

  /** The project's own name -- the last segment of its path -- not the whole path. */
  private fun sessionName(session: AgentClaudeSession): String {
    val source = session.cwd.ifBlank { session.project }
    val home = Format.homeFor(session.path) ?: Format.homeFor(source)
    return Format.shortPath(source, home).name.ifBlank { session.project.ifBlank { "session" } }
  }

  /**
   * Open pull requests, as the Mac's own `gh` sees them.
   *
   * The counts are of PRs, not of checks: "3 green" means three pull requests whose every finished
   * check passed, which is the question being asked. Summing check counts across PRs would give a
   * number in the hundreds that answers nothing.
   */
  private fun prsDashboard(): ModuleDashboard {
    val list = agentPrs
    val available = list?.available == true
    val prs = list?.items.orEmpty()
    val states =
        prs.map { Derive.prCheck(it.isDraft, it.checksSuccess, it.checksFailure, it.checksPending) }
    val green = states.count { it == Derive.PrCheck.Green }
    val red = states.count { it == Derive.PrCheck.Red }
    val pending = states.count { it == Derive.PrCheck.Pending }
    return ModuleDashboard(
        id = "prs",
        name = "Pull requests",
        meta = "gh search prs --author @me --state open",
        status =
            when {
              !available -> "no source"
              red > 0 -> "$red failing"
              else -> "${prs.size} open"
            },
        statusTone =
            when {
              !available -> StatusTone.Neutral
              red > 0 -> StatusTone.Crit
              else -> StatusTone.Ok
            },
        metrics =
            listOf(
                ModuleMetric("Open", if (available) "${prs.size}" else "n/a", "yours, plus extras"),
                ModuleMetric("Green", if (available) "$green" else "n/a", "all checks passed"),
                ModuleMetric("Red", if (available) "$red" else "n/a", "a check failed"),
                ModuleMetric("Waiting", if (available) "$pending" else "n/a", "checks running"),
            ),
        streamLabel = "gh",
        lines =
            summaryLines("gh search prs --author @me --state open", list) {
              "${it.repo}#${it.number}  ${Format.clip(it.title)}"
            },
        cursor = false,
        prompts = false,
        listLabel = "Open pull requests",
        rows = prs.mapIndexed { index, pr -> prRow(pr, states[index]) },
    )
  }

  private fun prRow(pr: AgentPr, check: Derive.PrCheck): ModuleRow =
      ModuleRow(
          title = "${pr.repo}#${pr.number} · ${pr.title}",
          subtitle =
              Format.parts(
                  pr.author.ifBlank { null },
                  "${pr.headRef} → ${pr.baseRef}",
                  Format.relativeTime(pr.updatedAt, System.currentTimeMillis()).ifBlank {
                    pr.updatedAt.ifBlank { null }
                  },
              ),
          // The merge state, not a second copy of the check state: `BLOCKED`
          // with every check green is the case worth seeing, and it is
          // GitHub's own word for it.
          trailing = pr.mergeState.lowercase(Locale.ROOT).ifBlank { "—" },
          tone =
              when (check) {
                Derive.PrCheck.Red -> StatusTone.Crit
                Derive.PrCheck.Green -> StatusTone.Ok
                Derive.PrCheck.Pending -> StatusTone.Run
                else -> StatusTone.Neutral
              },
          tag = check.label,
          tagTone =
              when (check) {
                Derive.PrCheck.Red -> TagTone.Sanguine
                Derive.PrCheck.Green -> TagTone.Ok
                Derive.PrCheck.Pending -> TagTone.Accent
                else -> TagTone.Outline
              },
          actions = prActions(pr),
      )

  /**
   * What can be done to a pull request from a phone.
   *
   * Merge is the one that goes through the confirmation dialog: everything else here is reversible
   * from the GitHub UI in a tap, and a merge is not. Ready is offered only on a draft, because `gh
   * pr ready` on an already-ready PR is an error message rather than an action.
   */
  private fun prActions(pr: AgentPr): List<RowAction> = buildList {
    add(RowAction("Approve", enabled = paired) { prAction(pr, "approve") })
    add(
        RowAction("Merge", enabled = paired, danger = true) {
          openDialog(DialogKind.MergePr(pr.repo, pr.number, pr.title))
        })
    add(
        RowAction(if (pr.autoMerge) "Auto-merge ✓" else "Auto-merge", enabled = paired) {
          prAction(pr, "auto_merge")
        })
    if (pr.isDraft) add(RowAction("Ready", enabled = paired) { prAction(pr, "ready") })
  }

  /**
   * The pull-request module in simulated mode.
   *
   * Two invented rows would be indistinguishable from two real ones, so there are none: the plate
   * says what the module needs and that nothing here is measuring it.
   */
  private fun simulatedPrsDashboard(): ModuleDashboard =
      ModuleDashboard(
          id = "prs",
          name = "Pull requests",
          meta = "gh · on the Mac",
          status = "simulated · no Mac",
          statusTone = StatusTone.Neutral,
          metrics =
              listOf(
                  ModuleMetric("Open", "n/a", "needs a paired Mac"),
                  ModuleMetric("Green", "n/a", "needs a paired Mac"),
                  ModuleMetric("Red", "n/a", "needs a paired Mac"),
              ),
          streamLabel = "gh",
          lines =
              listOf(
                  TerminalLine("$", "gh search prs --author @me --state open", TerminalTone.Text),
                  TerminalLine(" ", "no Mac is configured, so nothing ran", TerminalTone.Dim)),
          cursor = false,
          prompts = false,
          listLabel = "Open pull requests",
          rows =
              listOf(
                  ModuleRow(
                      "Nothing to show without a Mac",
                      "pair one and this lists your open PRs",
                      "n/a",
                      StatusTone.Neutral,
                  )),
      )

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
                    if (available) Format.formatBytes(v?.items?.sumOf { it.memoryBytes } ?: 0L)
                    else "n/a",
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
                  Format.parts(vm.arch, "${vm.cpus} cpu", Format.memoryBytes(vm.memoryBytes)),
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
    val argo = agentArgo
    val argoAvailable = argo?.available == true
    val apps = argo?.items.orEmpty()
    val synced = apps.count { it.sync.equals("Synced", ignoreCase = true) }
    val healthy = apps.count { it.health.equals("Healthy", ignoreCase = true) }
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
                ModuleMetric("Context", k?.detail?.ifBlank { "n/a" } ?: "n/a", "kubectl context"),
                ModuleMetric("Apps", if (argoAvailable) "${apps.size}" else "n/a", "ArgoCD"),
                ModuleMetric("Synced", if (argoAvailable) "$synced" else "n/a", "of ${apps.size}"),
                ModuleMetric(
                    "Healthy", if (argoAvailable) "$healthy" else "n/a", "of ${apps.size}"),
            ),
        streamLabel = "kubectl get nodes",
        lines =
            summaryLines("kubectl get nodes", k) {
              "${it.name}  ${if (it.ready) "Ready" else "NotReady"}  ${it.version}"
            },
        cursor = false,
        prompts = false,
        listLabel = "Nodes · ArgoCD",
        rows =
            (k?.items?.map { node ->
              ModuleRow(
                  node.name,
                  "${node.roles.joinToString(",").ifBlank { "no role" }} · ${node.version}",
                  if (node.ready) "ready" else "not ready",
                  if (node.ready) StatusTone.Ok else StatusTone.Crit,
              )
            } ?: emptyList()) + argoRows(),
    )
  }

  /**
   * The ArgoCD half of the homelab list.
   *
   * Broken first, and the healthy remainder as ONE row. Fifty applications in a phone-height list
   * is a scroll nobody performs, and the three that are out of sync were in the middle of it. When
   * kubectl cannot answer this is a single row carrying the cluster's own reason -- not an empty
   * space, which reads as "no applications".
   */
  private fun argoRows(): List<ModuleRow> {
    val argo = agentArgo ?: return emptyList()
    if (!argo.available) {
      return listOf(
          ModuleRow(
              title = "ArgoCD is not readable",
              subtitle = Format.clip(argo.reason.ifBlank { "kubectl said nothing about why" }),
              trailing = "n/a",
              tone = StatusTone.Neutral,
          ))
    }
    if (argo.items.isEmpty()) {
      return listOf(
          ModuleRow("No ArgoCD applications", "kubectl returned none", "0", StatusTone.Neutral))
    }
    val split = Derive.splitArgo(argo.items) { Derive.argoOk(it.sync, it.health) }
    val rows =
        split.attention.map { app ->
          ModuleRow(
              title = app.name,
              subtitle =
                  Format.parts(
                      "${app.sync.lowercase(Locale.ROOT)} · ${app.health.lowercase(Locale.ROOT)}",
                      app.namespace,
                      app.revision.ifBlank { null },
                      app.message.ifBlank { null }?.let(Format::clip),
                  ),
              trailing = app.revision.ifBlank { "—" },
              tone =
                  if (app.health.equals("Degraded", ignoreCase = true)) StatusTone.Crit
                  else StatusTone.Warn,
              tag = app.sync.lowercase(Locale.ROOT),
              tagTone = TagTone.Warn,
              actions =
                  listOf(
                      RowAction(
                          label = "Sync",
                          enabled = paired,
                          onClick = { openDialog(DialogKind.SyncApp(app.name, app.namespace)) },
                      )),
          )
        }
    if (split.restCount == 0) return rows
    return rows +
        ModuleRow(
            title = Derive.collapsedArgoLabel(split.restCount),
            subtitle = "nothing to do on these",
            trailing = "${split.restCount}",
            tone = StatusTone.Ok,
        )
  }

  /**
   * Why a module cannot mean anything on this Mac, or null if it can. Only answered while live and
   * only once the agent has said which tools exist; before that the gallery stays quiet rather than
   * guessing.
   */
  public fun moduleUnavailableReason(id: String): String? {
    val entry = MockHost.gallery.firstOrNull { it.id == id } ?: return null
    val needs = entry.requires ?: return null
    val tools = agentTools ?: return null
    if (agentUrl.isBlank()) return null
    val tool = tools.tools[needs] ?: return null
    return if (tool.available) null else "$needs is not on this Mac"
  }

  private fun antigravityDashboard(): ModuleDashboard {
    val ag = agentAntigravity
    val available = ag?.available == true
    val head = TerminalLine("$", "agy models", TerminalTone.Text)
    val lines =
        when {
          ag == null -> listOf(head, TerminalLine(" ", "asking…", TerminalTone.Dim))
          !ag.available -> listOf(head, TerminalLine(" ", ag.reason, TerminalTone.Warn))
          else ->
              listOf(head) +
                  ag.models.map { (id, label) ->
                    TerminalLine(" ", "$id  $label", TerminalTone.Dim)
                  }
        }
    return ModuleDashboard(
        id = "antigravity",
        name = "Antigravity",
        meta = "agy models · agy agents",
        status = if (available) "v${ag?.version}" else "no source",
        statusTone = if (available) StatusTone.Ok else StatusTone.Neutral,
        metrics =
            listOf(
                ModuleMetric(
                    "Version",
                    if (available) ag?.version.orEmpty() else "n/a",
                    "as agy reports it"),
                ModuleMetric(
                    "Models", if (available) "${ag?.models?.size ?: 0}" else "n/a", "it can run"),
                ModuleMetric(
                    "Agents", if (available) "${ag?.agents?.size ?: 0}" else "n/a", "configured"),
            ),
        streamLabel = "agy models",
        lines = lines,
        cursor = false,
        prompts = false,
        listLabel = "Agents",
        rows =
            if (ag?.agents.isNullOrEmpty())
                listOf(
                    ModuleRow(
                        "No agents configured",
                        "agy agents printed nothing",
                        "0",
                        StatusTone.Neutral))
            else ag!!.agents.map { ModuleRow(it, "agy agent", "ok", StatusTone.Ok) },
    )
  }

  private fun grafanaDashboard(): ModuleDashboard {
    val r = promqlResult
    val head = TerminalLine("$", promql, TerminalTone.Text)
    val lines =
        when {
          r == null -> listOf(head, TerminalLine(" ", promqlStatus, TerminalTone.Dim))
          !r.available -> listOf(head, TerminalLine(" ", r.reason, TerminalTone.Warn))
          else ->
              listOf(
                  head,
                  TerminalLine(" ", "${r.resultType} · ${r.seriesCount} series", TerminalTone.Ok))
        }
    val name = { labels: Map<String, String> ->
      labels["instance"]
          ?: labels["__name__"]
          ?: labels.entries.firstOrNull()?.let { "${it.key}=${it.value}" }
          ?: "series"
    }
    return ModuleDashboard(
        id = "grafana",
        name = "Grafana panel",
        meta = "PromQL, run on the Mac",
        status = if (r?.available == true) "${r.seriesCount} series" else promqlStatus,
        statusTone = if (r?.available == true) StatusTone.Ok else StatusTone.Neutral,
        metrics =
            listOf(
                ModuleMetric(
                    "Series",
                    if (r?.available == true) "${r.seriesCount}" else "n/a",
                    r?.resultType.orEmpty().ifBlank { "run a query" }),
                ModuleMetric(
                    "First value",
                    r?.firstValue?.let { "%.4g".format(it) } ?: "n/a",
                    "newest sample"),
                // The value slot is one short line of 26 sp display type;
                // a metric name is longer than that every time, so the
                // query goes in the sub-line and the value names the kind.
                ModuleMetric("Query", "PromQL", promql),
            ),
        streamLabel = "query",
        lines = lines,
        cursor = false,
        prompts = false,
        listLabel = "Series",
        rows =
            r?.series?.take(SERIES_ROWS)?.map { s ->
              ModuleRow(
                  name(s.labels),
                  s.labels
                      .filterKeys { it != "instance" && it != "__name__" }
                      .entries
                      .take(3)
                      .joinToString(" · ") { "${it.key}=${it.value}" }
                      .ifBlank { "no other labels" },
                  s.value?.let { "%.4g".format(it) } ?: "n/a",
                  StatusTone.Ok)
            } ?: emptyList(),
    )
  }

  private fun ollamaDashboard(): ModuleDashboard {
    val o = agentOllama
    val available = o?.available == true
    val loaded = o?.running?.size ?: 0
    val models = o?.models ?: emptyList()
    val head = TerminalLine("$", "ollama ps", TerminalTone.Text)
    val lines =
        when {
          o == null -> listOf(head, TerminalLine(" ", "asking…", TerminalTone.Dim))
          !o.available -> listOf(head, TerminalLine(" ", o.reason, TerminalTone.Warn))
          o.running.isEmpty() ->
              listOf(head, TerminalLine(" ", "no model loaded", TerminalTone.Dim))
          else ->
              listOf(head) +
                  o.running.map {
                    TerminalLine(
                        " ",
                        "${it.name}  ${it.processor}  ctx ${it.context}  ${it.until}",
                        TerminalTone.Ok)
                  }
        }
    return ModuleDashboard(
        id = "ollama",
        name = "Ollama",
        meta = "ollama list · ollama ps",
        status =
            when {
              !available -> "no source"
              loaded > 0 -> "$loaded loaded"
              else -> "idle"
            },
        statusTone = if (available) StatusTone.Ok else StatusTone.Neutral,
        metrics =
            listOf(
                ModuleMetric("Models", if (available) "${models.size}" else "n/a", "installed"),
                ModuleMetric("Loaded", if (available) "$loaded" else "n/a", "in memory now"),
                ModuleMetric(
                    "On disk",
                    if (available) Format.formatBytes(models.sumOf { it.sizeBytes }) else "n/a",
                    "all models"),
            ),
        streamLabel = "ollama ps",
        lines = lines,
        cursor = false,
        prompts = false,
        listLabel = "Models",
        rows =
            models.map { m ->
              val running = o?.running?.any { it.name == m.name } == true
              ModuleRow(
                  m.name,
                  Format.parts(Format.formatBytes(m.sizeBytes), m.modified),
                  if (running) "loaded" else "on disk",
                  if (running) StatusTone.Ok else StatusTone.Neutral,
              )
            },
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
        status = moduleUnavailableReason(id) ?: "no data source yet",
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
                    moduleUnavailableReason(id) ?: "Not wired to this Mac yet",
                    if (moduleUnavailableReason(id) != null)
                        "install it on the Mac and it will show up here"
                    else "the agent has no endpoint for it",
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

  /**
   * The PromQL panel's own rows, for the Mac screen.
   *
   * Empty until a query has come back, which is what keeps the dashed placeholder on screen. There
   * is still no chart here -- the panel shows the series and their newest values, which is what the
   * reply actually contains.
   */
  public val promqlPanelRows: List<PanelRow>
    get() {
      val result = promqlResult ?: return emptyList()
      if (!result.available) return emptyList()
      return result.series.take(PANEL_ROWS).map { series ->
        PanelRow(
            name =
                series.labels["instance"]
                    ?: series.labels["__name__"]
                    ?: series.labels.entries.firstOrNull()?.let { "${it.key}=${it.value}" }
                    ?: "series",
            value = series.value?.let { "%.4g".format(it) } ?: "n/a",
        )
      }
    }

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
      // Counted in milliseconds rather than in ticks because the tick length
      // is a user setting: at "30 s" a count of ticks would ask GitHub every
      // half hour, and at "1 s" every minute, for the same "every 60 s".
      msSincePrPoll += step
      // The trust countdown reads against this, so it advances with the rest
      // of the screen instead of freezing at whatever it said when the last
      // tool ran.
      bridgeNowMs = System.currentTimeMillis()
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
    updateSelected { it.copy(token = token) }
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
    // The panel module is the query's table; open it and the query runs.
    if (id == "grafana" && promqlResult == null && agentUrl.isNotBlank()) runPromql()
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

  /**
   * Switches Macs.
   *
   * Everything derived from the old host is dropped, not carried over: the process list, the VMs,
   * the container list and the last metrics all belonged to a different machine, and leaving them
   * on screen under a new name is the most convincing lie this app could tell.
   */
  public fun selectHost(id: String) {
    if (id == selectedHostId) return
    val entry = hosts.firstOrNull { it.id == id } ?: return
    selectedHostId = id
    persistence.selectedHostId = id
    agentUrlDraft = entry.url
    hostAliasDraft = entry.alias
    resetHostSnapshots()
    log("info", "host · switched to ${entry.alias.ifBlank { entry.url }}")
  }

  /** Adds a Mac and switches to it. Pairing is per host, so the new one starts unpaired. */
  public fun addHost(url: String) {
    val trimmed = url.trim()
    if (trimmed.isBlank()) return
    val entry =
        AgentHostEntry(
            id = "host-${System.currentTimeMillis()}",
            alias = HostCodec.aliasFor(trimmed),
            url = trimmed,
            token = "",
            mac = "",
        )
    hosts = hosts + entry
    persistence.hosts = hosts
    newHostDraft = ""
    selectedHostId = entry.id
    persistence.selectedHostId = entry.id
    agentUrlDraft = entry.url
    hostAliasDraft = entry.alias
    resetHostSnapshots()
    regeneratePairCode()
    log("info", "host · added ${entry.alias} · ${AgentClient.normalize(entry.url)}")
  }

  /**
   * Forgets one Mac, and its token with it.
   *
   * The token goes because a phone with no host holding a key that still opens it is the worst of
   * both. Removing the selected one falls back to whatever is left, or to the simulated state.
   */
  public fun forgetHost(id: String) {
    val entry = hosts.firstOrNull { it.id == id } ?: return
    hosts = hosts.filterNot { it.id == id }
    persistence.hosts = hosts
    if (id == selectedHostId) {
      val next = hosts.firstOrNull()
      selectedHostId = next?.id.orEmpty()
      persistence.selectedHostId = selectedHostId
      agentUrlDraft = next?.url.orEmpty()
      hostAliasDraft = next?.alias.orEmpty()
      // Before the log line, not after: the reset clears the event stream,
      // which belonged to the Mac that was just forgotten.
      resetHostSnapshots()
      regeneratePairCode()
    }
    log("info", "host · forgot ${entry.alias.ifBlank { entry.url }}")
  }

  public fun updateHostAliasDraft(value: String) {
    hostAliasDraft = value
  }

  public fun updateNewHostDraft(value: String) {
    newHostDraft = value
  }

  /** Adds the Mac typed into the "Add a Mac" row. */
  public fun addTypedHost() {
    addHost(newHostDraft)
  }

  /** Rewrites the selected entry in place, in state and on disk together. */
  private fun updateSelected(transform: (AgentHostEntry) -> AgentHostEntry) {
    val current = selectedHost ?: return
    hosts = hosts.map { if (it.id == current.id) transform(it) else it }
    persistence.hosts = hosts
  }

  public fun toggleTheme() {
    darkTheme = !darkTheme
    persistence.darkTheme = darkTheme
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
    moduleUnavailableReason(id)?.let { why ->
      if (id !in installed) {
        log("warn", "module · $name · $why")
        return
      }
    }
    if (id in installed) {
      installed.remove(id)
      log("info", "module · $name removed")
    } else {
      installed.add(id)
      log("ok", "module · $name installed")
    }
    persistence.installed = installed.toList()
  }

  public fun sideload(): Unit = log("warn", "module · sideload by URL is not implemented yet")

  public fun openInstallGuide(): Unit =
      log(
          "warn",
          "pairing · install guide not written yet; see mobile/android/remote/macagent/README.md")

  /**
   * Runs a macro on the Mac.
   *
   * This used to print `ok — done` unconditionally, which was a lie in the one case that matters:
   * when nothing ran. Now either the command's real output lands in the console, or the log says
   * the phone is not paired and nothing else happens.
   */
  public fun runMacro(macro: Macro) {
    stream(
        what = "macro · ${macro.label}",
        kind = execKind(macro.kind),
        command = macro.command,
        onLine = { stream, text -> emit(terminalLine(stream, text)) },
        onEnd = { result -> emit(exitLine(result)) },
        onError = { emitFailure("macro · ${macro.label}", it) },
    ) {
      emit(TerminalLine("$", macro.command, TerminalTone.Text))
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
        HidAction.DisplaySleepChord -> "sleep the display"
        HidAction.LockScreen -> "lock the screen"
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
   * Names the selected Mac, or clears the name.
   *
   * Applied on a button for the same reason the URL is: every keystroke would otherwise rename the
   * machine in the top bar, the rail and three screen headers at once.
   */
  public fun saveHostAlias() {
    val next = hostAliasDraft.trim()
    if (next == selectedHost?.alias.orEmpty()) return
    updateSelected { it.copy(alias = next) }
    log("info", if (next.isBlank()) "host · name cleared" else "host · now called \"$next\"")
  }

  /**
   * Points the app at an agent, or at none.
   *
   * Applied on a button rather than per keystroke: a URL typed one character at a time is a dozen
   * unreachable hosts in a row, and each would have logged a warning.
   */
  public fun applyAgentUrl() {
    val next = agentUrlDraft.trim()
    // Nothing saved yet: Connect on an empty list is how the first Mac is
    // added, so it means the same thing as the Add row.
    if (selectedHost == null) {
      if (next.isNotBlank()) addHost(next)
      return
    }
    // A new address is a different machine until proven otherwise: the token
    // paired with the old one would only ever come back 403.
    val changed = next != selectedHost?.url
    updateSelected { it.copy(url = next, token = if (changed) "" else it.token) }
    if (next.isNotBlank()) agentUrlDraft = AgentClient.normalize(next).substringAfter("://")
    if (changed) regeneratePairCode()
    resetHostSnapshots()
    if (next.isBlank()) {
      log("info", "agent · none configured, dashboards simulated")
    } else {
      log("info", "agent · ${AgentClient.normalize(next)}")
    }
  }

  /**
   * Everything derived from a host, dropped.
   *
   * Called whenever the app starts pointing somewhere else. The tag goes back to unreachable rather
   * than live, because not a single byte has come back from the new address yet.
   */
  private fun resetHostSnapshots() {
    agentMetrics = null
    agentHost = null
    agentError = ""
    agentProcesses = null
    agentVms = null
    agentOllama = null
    agentTools = null
    agentAntigravity = null
    promqlResult = null
    agentContainers = null
    agentK8s = null
    agentSessions = null
    agentAudio = null
    gpuWatts = null
    aneWatts = null
    powerQueryReason = ""
    agentClaudeSessions = null
    agentPrs = null
    agentArgo = null
    pollsSinceHost = 0
    sawUnreachable = false
    // Due immediately: the new host's PRs are a different list, and waiting a
    // minute to find that out would show the old Mac's for that minute.
    msSincePrPoll = PR_POLL_MS
    if (agentUrl.isNotBlank()) {
      // The demo lines were seeded for a phone with no Mac. Now there is one.
      terminal.clear()
      agentTranscript.clear()
      logs.clear()
    }
    // Unreachable until proven otherwise: the tag must not say "live" before a
    // single byte has come back from THIS host.
    metricsSource = if (agentUrl.isBlank()) MetricsSource.Simulated else MetricsSource.Unreachable
  }

  /**
   * Forget the agent, and the token with it.
   *
   * Leaving the token behind would be the worst of both: a phone with no host, holding a key that
   * still opens it. The next pairing issues a fresh one anyway.
   */
  public fun forgetAgent() {
    val current = selectedHost ?: return
    forgetHost(current.id)
  }

  private var pollsSinceHost = 0

  /** Whether the selected Mac has dropped out since it was last live, so "back" means something. */
  private var sawUnreachable = false

  /**
   * One poll of the agent. Failure freezes the numbers where they are and says so; it does NOT
   * resume the simulated walk, because motion over a stale reading is the most misleading thing a
   * dashboard can do.
   */
  private var pollCount = 0
  private var msSincePrPoll = Long.MAX_VALUE / 2

  private suspend fun pollAgent() {
    val client = AgentClient(agentUrl, agentToken)
    val result = runCatching {
      // Host identity changes never; refresh it rarely so a renamed machine
      // or an upgraded agent shows up without a restart.
      if (agentHost == null || pollsSinceHost >= HOST_REFRESH_POLLS) {
        val h = client.host()
        agentHost = h
        if (h.macAddress.isNotBlank() && h.macAddress != agentMac) {
          updateSelected { entry -> entry.copy(mac = h.macAddress) }
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
            // Only on the transition, and only when something was there to
            // come back FROM: a first successful poll after launch is not a
            // recovery and does not deserve a notification.
            if (metricsSource == MetricsSource.Unreachable && sawUnreachable) {
              post("host", "$hostShortName is back", "the agent is answering again", Screen.Home)
            }
            sawUnreachable = false
          }
          metricsSource = MetricsSource.Live
          agentError = ""
        }
        .onFailure { e ->
          val message = e.message ?: e::class.simpleName ?: "error"
          if (metricsSource == MetricsSource.Live) {
            log("warn", "agent · unreachable: $message")
            // The switch used to change only a dialog's wording. Now it does
            // what it says: one magic packet the moment a live Mac stops
            // answering, not one per tick -- a Mac that is off for the night
            // does not need a packet every second.
            if (wakeOnLan && agentMac.isNotBlank()) {
              log("info", "power · Wake-on-LAN sent, the Mac stopped answering")
              scope.launch { wakeHost() }
            }
            sawUnreachable = true
            post("host", "$hostShortName is unreachable", message, Screen.Hosts)
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
    // Claude Code sessions are the one v1.2 read that changes second to
    // second: "waiting for permission" is only useful while it is still true.
    runCatching { client.claudeSessions() }.onSuccess { agentClaudeSessions = it }
    // GitHub is somebody else's rate limit, and a PR's checks do not move in
    // under a minute.
    if (msSincePrPoll >= PR_POLL_MS) {
      msSincePrPoll = 0
      runCatching { client.prs() }.onSuccess { agentPrs = it }
    }
    if (pollCount % SLOW_POLL_EVERY != 1) return
    runCatching { client.argocd() }.onSuccess { agentArgo = it }
    runCatching { client.vms() }.onSuccess { agentVms = it }
    runCatching { client.ollama() }.onSuccess { agentOllama = it }
    runCatching { client.tools() }.onSuccess { agentTools = it }
    runCatching { client.antigravity() }.onSuccess { agentAntigravity = it }
    runCatching { client.containers() }.onSuccess { agentContainers = it }
    runCatching { client.k8s() }.onSuccess { agentK8s = it }
    runCatching { client.sessions() }.onSuccess { agentSessions = it }
    // Flags on the Mac, so this changes only when the agent is restarted.
    runCatching { client.notifyStatus() }.onSuccess { agentNotify = it }
    pollPower(client)
  }

  /**
   * GPU and Neural Engine power, in watts, if anything is exporting them.
   *
   * These two metrics come from `tools/ops/macos-power-agent`, which runs `powermetrics` as root and
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
    // Held by identity, not by index. The answer's lines are appended as they
    // arrive, so by the time the placeholder is removed everything after it has
    // shifted -- and an index would then delete a line of the reply.
    val placeholder = TerminalLine(" ", "thinking…", TerminalTone.Dim)
    var first = true
    stream(
        what = "claude code · prompt",
        kind = ExecKind.Claude,
        command = text,
        timeoutSeconds = CLAUDE_TIMEOUT_S,
        onLine = { _, line ->
          // The placeholder is swapped for the FIRST line rather than left
          // above the answer: "thinking…" sitting over a finished reply reads
          // as a turn still in flight.
          if (first) {
            first = false
            agentTranscript.remove(placeholder)
          }
          agentTranscript.add(TerminalLine(" ", line, TerminalTone.Dim))
        },
        onEnd = { result ->
          agentTranscript.remove(placeholder)
          if (result.cancelled) {
            agentTranscript.add(TerminalLine(" ", "stopped", TerminalTone.Warn))
          } else if (result.exitCode != 0) {
            agentTranscript.add(
                TerminalLine(" ", "claude exited ${result.exitCode}", TerminalTone.Err))
          }
        },
        onError = {
          agentTranscript.remove(placeholder)
          agentTranscript.add(TerminalLine(" ", failureText(it), TerminalTone.Err))
          actFailed("claude code · prompt", it)
        },
    ) {
      // Only once the prompt is genuinely on its way. Adding the question and
      // a "thinking…" line for a prompt that was refused -- not paired, or
      // something else already running -- would leave the transcript waiting
      // for an answer that nothing is coming back with.
      agentTranscript.add(TerminalLine("›", text, TerminalTone.Text))
      agentTranscript.add(placeholder)
      prompt = ""
      openModule("claude")
      log("info", "claude code · prompt relayed")
    }
  }

  /** Picks the session a supplemental instruction goes to; tapping the selected one clears it. */
  public fun selectSession(id: String) {
    selectedSessionId = if (selectedSessionId == id) null else id
  }

  /**
   * Send, on the Claude module.
   *
   * With a session selected this RESUMES that conversation -- `claude --resume <id>` on the Mac --
   * rather than starting a fresh one, which is the whole point of the sessions list. With none
   * selected it falls back to [sendPrompt], and the transcript says which of the two happened.
   *
   * `/v1/claude/resume` is not a streaming endpoint, so there is nothing to show while it runs: the
   * "running…" line is a placeholder that the reply replaces, exactly as `thinking…` is above.
   */
  public fun sendModulePrompt() {
    val session = selectedSession
    if (session == null) {
      sendPrompt()
      return
    }
    val text = prompt.trim()
    if (text.isEmpty()) return
    val client = actClient("claude code · resume") ?: return
    if (commandRunning) {
      log("warn", "claude code · resume · \"$runningLabel\" is still running · stop it first")
      return
    }
    val placeholder = TerminalLine(" ", "running…", TerminalTone.Dim)
    agentTranscript.add(TerminalLine("›", text, TerminalTone.Text))
    agentTranscript.add(placeholder)
    prompt = ""
    openModule("claude")
    log("info", "claude code · resumed ${sessionName(session)}")
    commandRunning = true
    runningLabel = "resume ${sessionName(session)}"
    scope.launch {
      runCatching { client.claudeResume(session.sessionId, text) }
          .onSuccess { result ->
            agentTranscript.remove(placeholder)
            val body = (result.stdout + result.stderr).trim()
            if (body.isEmpty()) {
              agentTranscript.add(TerminalLine(" ", "claude printed nothing", TerminalTone.Dim))
            } else {
              body.lineSequence().forEach {
                agentTranscript.add(TerminalLine(" ", it, TerminalTone.Dim))
              }
            }
            if (result.exitCode != 0) {
              agentTranscript.add(
                  TerminalLine(" ", "claude exited ${result.exitCode}", TerminalTone.Err))
            }
          }
          .onFailure {
            agentTranscript.remove(placeholder)
            agentTranscript.add(TerminalLine(" ", failureText(it), TerminalTone.Err))
            actFailed("claude code · resume", it)
          }
      commandRunning = false
      runningLabel = ""
    }
  }

  // --- pull requests ----------------------------------------------------

  /**
   * One `gh` action on one pull request.
   *
   * gh's own stdout is logged rather than a "done": `gh pr merge` on a blocked PR exits non-zero
   * with a sentence explaining why, and that sentence is the only useful thing on the screen.
   */
  public fun prAction(pr: AgentPr, action: String) {
    val what = "pr · ${pr.repo}#${pr.number} · ${action.replace('_', ' ')}"
    val client = actClient(what) ?: return
    log("info", "$what · sent")
    scope.launch {
      runCatching { client.prAction(pr.repo, pr.number, action) }
          .onSuccess { result ->
            val output =
                Format.clip(
                    result.output.lineSequence().firstOrNull { it.isNotBlank() }
                        ?: (if (result.ok) "gh printed nothing" else "gh failed and said nothing"))
            log(if (result.ok) "ok" else "warn", "$what · $output")
            // The list is a minute stale by contract; after acting on it that
            // is a minute of showing the state the action just changed.
            refreshPrs()
          }
          .onFailure { actFailed(what, it) }
    }
  }

  /** Asks for the PR list again now, rather than at the next 60 s tick. */
  private fun refreshPrs() {
    val client = AgentClient(agentUrl, agentToken)
    scope.launch {
      runCatching { client.prs() }
          .onSuccess {
            agentPrs = it
            msSincePrPoll = 0
          }
    }
  }

  // --- screen peek ------------------------------------------------------

  /** Opens the peek plate, and takes the first capture. Closing throws the image away. */
  public fun togglePeek(width: Int) {
    peekOpen = !peekOpen
    peekRegion = Derive.PeekRegion.Full
    if (!peekOpen) {
      // Not kept for the next open: a stale screenshot of a Mac is exactly
      // the kind of thing that gets read as live.
      peekImage = null
      peekReason = ""
      return
    }
    capturePeek(width)
  }

  public fun closePeek() {
    peekOpen = false
    peekImage = null
    peekReason = ""
    peekRegion = Derive.PeekRegion.Full
  }

  /**
   * One screenshot of the Mac's main display.
   *
   * [AgentUnavailableException] is caught separately and its reason shown VERBATIM: macOS refusing
   * for want of a Screen Recording grant is the expected answer on a fresh Mac, and the remedy is a
   * sentence the agent already wrote.
   */
  public fun capturePeek(width: Int) {
    val client = actClient("screen · peek") ?: return
    if (peekLoading) return
    peekLoading = true
    peekReason = ""
    val region = peekRegion
    scope.launch {
      runCatching { client.screen(width, region) }
          .onSuccess {
            peekImage = it
            peekReason = ""
          }
          .onFailure { error ->
            peekImage = null
            peekReason =
                if (error is AgentUnavailableException) error.reason else failureText(error)
            actFailed("screen · peek", error)
          }
      peekLoading = false
    }
  }

  /**
   * A pinch settled: show that part of the display, at native detail.
   *
   * Nothing happens for a pinch that lands where the plate already is, so a finger that wobbles
   * without zooming does not cost a screencapture on the Mac.
   */
  public fun zoomPeek(region: Derive.PeekRegion, width: Int): Boolean {
    if (region == peekRegion) return false
    peekRegion = region
    capturePeek(width)
    return true
  }

  /** Double-tap: back to the whole display. True when a capture was started. */
  public fun resetPeekZoom(width: Int): Boolean {
    if (peekRegion.isFull) return false
    peekRegion = Derive.PeekRegion.Full
    capturePeek(width)
    return true
  }

  // --- notifications ----------------------------------------------------

  /** What the Mac would do with a notification, for the Hosts plate. */
  public val notifyLine: String
    get() {
      val n = agentNotify ?: return "push · the agent has not said yet"
      return if (n.configured) "push · topic ${n.topic.ifBlank { "unnamed" }}"
      else "push · not configured on the Mac"
    }

  /** Asks the Mac to publish one test notification. Proves the whole path, not just the flags. */
  public fun testPush() {
    val client = actClient("notify · test") ?: return
    scope.launch {
      runCatching { client.notifyTest() }
          .onSuccess { log("ok", "notify · test published") }
          .onFailure { actFailed("notify · test", it) }
    }
  }

  public fun updateCommand(value: String) {
    command = value
  }

  /** Runs the console line on the Mac through `/bin/zsh -lc`, and remembers it. */
  public fun runCommand() {
    val text = command.trim()
    if (text.isEmpty()) return
    stream(
        what = "console · $text",
        kind = ExecKind.Shell,
        command = text,
        onLine = { stream, line -> emit(terminalLine(stream, line)) },
        onEnd = { result -> emit(exitLine(result)) },
        onError = { emitFailure("console", it) },
    ) {
      emit(TerminalLine("$", text, TerminalTone.Text))
      command = ""
      remember(text)
    }
  }

  /**
   * Runs a command and shows its output as it arrives.
   *
   * The whole reason `/v1/exec/stream` exists on the agent: `/v1/exec` answers once, at the end, so
   * a four-minute build was four minutes of a screen that could not distinguish "working" from
   * "hung". [started] runs only if the command is actually going to be sent -- it is what prints
   * the `$ command` line and clears the input, and doing that for a command that was refused
   * because the phone is not paired would leave a prompt on screen for something that never ran.
   */
  private fun stream(
      what: String,
      kind: ExecKind,
      command: String,
      timeoutSeconds: Int = 0,
      onLine: (String, String) -> Unit,
      onEnd: (ExecResult) -> Unit,
      onError: (Throwable) -> Unit,
      started: () -> Unit,
  ) {
    val client = actClient(what) ?: return
    // One at a time, and said out loud. Two streams into one terminal would
    // interleave line by line with nothing to say which was which.
    if (commandRunning) {
      log("warn", "$what · \"$runningLabel\" is still running · stop it first")
      return
    }
    started()
    val handle = ExecStreamHandle()
    runningHandle = handle
    commandRunning = true
    runningLabel = command.take(RUNNING_LABEL_MAX)
    scope.launch {
      runCatching {
            client.execStream(kind, command, timeoutSeconds, handle) { stream, text ->
              // The callback lands on an IO thread and these lists are read by
              // Compose; the hop back is not optional.
              scope.launch { onLine(stream, text) }
            }
          }
          .onSuccess { result ->
            onEnd(result)
            notifyFinished(command, result)
          }
          .onFailure { onError(it) }
      commandRunning = false
      runningLabel = ""
      runningHandle = null
    }
  }

  /**
   * Hangs up on the running command.
   *
   * Closing the connection IS the cancellation: the agent kills the process group when the phone
   * disconnects, so there is no "please stop" for the Mac to ignore.
   */
  public fun stopCommand() {
    val handle = runningHandle
    if (handle == null) {
      log("warn", "console · nothing is running")
      return
    }
    handle.cancel()
    log("warn", "console · stopped \"$runningLabel\"")
  }

  /** One streamed line, coloured by the pipe it came from. */
  private fun terminalLine(stream: String, text: String): TerminalLine =
      TerminalLine(" ", text, if (stream == "stderr") TerminalTone.Warn else TerminalTone.Text)

  /**
   * How a streamed command ended.
   *
   * `exit 0` is printed even on success: a command that produced no output and one that failed look
   * identical without it. A cancelled command says so instead of inventing a code.
   */
  private fun exitLine(result: ExecResult): TerminalLine =
      if (result.cancelled) TerminalLine(" ", "stopped", TerminalTone.Warn)
      else
          TerminalLine(
              " ",
              "exit ${result.exitCode}",
              if (result.exitCode == 0) TerminalTone.Ok else TerminalTone.Err,
          )

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
    // Read once into a local: `dialog` is a Compose state property, which
    // cannot be smart-cast, and the branches below need the target the dialog
    // was opened for.
    when (val open = dialog) {
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
      // Merging is the one PR action that cannot be undone from a phone, so
      // it is the one that comes through here.
      is DialogKind.MergePr -> {
        val target = open
        val what = "pr · ${target.repo}#${target.number} · merge"
        val client = actClient(what)
        if (client != null) {
          log("warn", "$what · sent")
          scope.launch {
            runCatching { client.prAction(target.repo, target.number, "merge") }
                .onSuccess { result ->
                  val output =
                      Format.clip(
                          result.output.lineSequence().firstOrNull { it.isNotBlank() }
                              ?: (if (result.ok) "merged" else "gh failed and said nothing"))
                  log(if (result.ok) "ok" else "warn", "$what · $output")
                  refreshPrs()
                }
                .onFailure { actFailed(what, it) }
          }
        }
      }
      is DialogKind.SyncApp -> {
        val target = open
        val what = "argocd · ${target.namespace}/${target.name} · sync"
        val client = actClient(what)
        if (client != null) {
          log("warn", "$what · sent")
          scope.launch {
            runCatching { client.argoSync(target.name, target.namespace) }
                .onSuccess { result ->
                  val output =
                      Format.clip(
                          result.output.lineSequence().firstOrNull { it.isNotBlank() }
                              ?: (if (result.ok) "patched" else "kubectl said nothing"))
                  log(if (result.ok) "ok" else "warn", "$what · $output")
                }
                .onFailure { actFailed(what, it) }
          }
        }
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
            promqlResult = result
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
      log(
          "warn",
          "power · the magic packet could not be sent · ${wakeFailure.ifBlank { "no reason given" }}")
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

  /** Why the last magic packet did not leave the phone, for the log line that says it did not. */
  private var wakeFailure: String = ""

  /** True when at least one of the two datagrams left the phone. */
  private fun broadcast(packet: ByteArray): Boolean {
    val targets = buildList {
      add("255.255.255.255")
      if (agentUrl.isNotBlank()) add(agentHostLabel().substringBefore(':'))
    }
    var sent = false
    wakeFailure = ""
    runCatching {
          DatagramSocket().use { socket ->
            socket.broadcast = true
            targets.forEach { target ->
              runCatching {
                    val address = InetAddress.getByName(target)
                    socket.send(DatagramPacket(packet, packet.size, address, WakeOnLan.PORT))
                  }
                  .onSuccess { sent = true }
                  // Kept, not swallowed: "could not be sent" with no reason
                  // is indistinguishable from a bug. On the Fold it was the
                  // phone's own network dropping mid-fold, and the message
                  // said so once it was allowed to.
                  .onFailure { wakeFailure = failureText(it) }
            }
          }
        }
        .onFailure { wakeFailure = failureText(it) }
    return sent
  }

  /**
   * Retry is a real poll, now, not a log line pretending to be one. The result -- live or still
   * unreachable -- lands through the same path a scheduled tick uses, so the tag and the numbers
   * say whatever is actually true.
   */
  public fun retryHost() {
    if (agentUrl.isBlank()) {
      log("warn", "host · no agent configured to retry")
      return
    }
    log("info", "host · retrying ${AgentClient.normalize(agentUrl)}")
    scope.launch { pollAgent() }
  }

  /** Called by the activity: whether anyone is actually looking at this. */
  public fun onForeground(value: Boolean) {
    foreground = value
  }

  // --- the phone bridge -------------------------------------------------

  /** Whether the bridge can be operated at all: false in previews and tests. */
  public val bridgeAvailable: Boolean
    get() = bridge != null

  /** The trust window in words: "closed", or how long is left. */
  public val trustRemaining: String
    get() = BridgePolicy.trustRemaining(trustUntil, bridgeNowMs)

  public val trustOpen: Boolean
    get() = BridgePolicy.trustOpen(trustUntil, bridgeNowMs)

  /**
   * The bridge told us something. Called on the main thread by the activity's adapter.
   *
   * One call carrying everything rather than five setters: the link state, the window and the audit
   * trail change together when a tool runs, and a UI that learned about them one at a time would
   * paint an approval that had already been answered.
   */
  public fun onBridgeStatus(status: BridgeStatus) {
    bridgeEnabled = status.enabled
    bridgeLinked = status.linked
    bridgeLinkStatus = status.link
    trustUntil = status.trustUntil
    pendingApproval = status.pending
    bridgeAudit = status.audit
    bridgeNowMs = System.currentTimeMillis()
  }

  /** Re-reads the permission rows. Cheap, and the answer changes while the app is in the back. */
  public fun refreshBridgePermissions() {
    bridgePermissions = bridge?.permissions() ?: emptyList()
    bridgeNowMs = System.currentTimeMillis()
  }

  /** The switch on the Hosts plate. */
  public fun updateBridgeEnabled(value: Boolean) {
    val control = bridge
    if (control == null) {
      log("warn", "bridge · not available in this build")
      return
    }
    bridgeEnabled = value
    persistence.bridgeEnabled = value
    control.setEnabled(value)
    log(if (value) "ok" else "info", "bridge · ${if (value) "started" else "stopped"}")
  }

  /** "Trust agents for 1 hour". */
  public fun trustAgents() {
    bridge?.trustForAnHour()
    log("warn", "bridge · agents trusted for 1 hour")
  }

  /** "End trust", for when an hour turns out to have been optimistic. */
  public fun endTrust() {
    bridge?.endTrust()
    log("ok", "bridge · trust ended")
  }

  public fun approvePending() {
    val question = pendingApproval?.question.orEmpty()
    bridge?.answer(true)
    log("warn", "bridge · approved · $question")
  }

  public fun denyPending() {
    val question = pendingApproval?.question.orEmpty()
    bridge?.answer(false)
    log("ok", "bridge · denied · $question")
  }

  /** The Grant button on a permission row. */
  public fun grantBridgePermission(id: String) {
    bridge?.grant(id)
  }

  /**
   * A phone-local notification, or nothing.
   *
   * Nothing when there is no notifier (previews and tests). The deep link is what makes a
   * notification worth tapping: it opens the screen the message is about rather than wherever the
   * app happened to be.
   */
  private fun post(id: String, title: String, body: String, screen: Screen) {
    notifier?.notify(id, title, body, DeepLink.uriFor(screen.name.lowercase(Locale.ROOT)))
  }

  /**
   * Tells the user a command finished, but only if they were not watching.
   *
   * A notification for output that is already on screen in front of them is noise, and noise is how
   * a notification channel gets turned off for the one message that mattered.
   */
  private fun notifyFinished(command: String, result: ExecResult) {
    if (foreground || result.cancelled) return
    post(
        id = "exec",
        title = "Command finished · exit ${result.exitCode}",
        body = command.take(NOTIFY_BODY_MAX),
        screen = Screen.Console,
    )
  }

  /**
   * A Quick Settings tile firing while the app was not running.
   *
   * The tile can be tapped from the lock screen, seconds before Bluetooth has finished connecting,
   * so this waits rather than failing instantly -- and when the wait runs out it says which of the
   * three link states it gave up in, because "nothing happened" is the one answer that teaches
   * nobody anything.
   */
  public fun runTileAction(action: HidAction) {
    val label = desktopLabel(action)
    scope.launch {
      repeat((TILE_HID_WAIT_MS / TILE_HID_POLL_MS).toInt()) {
        if (hidLink == HidLinkState.Connected) {
          sendHid(action)
          log("ok", "tile · $label sent")
          return@launch
        }
        delay(TILE_HID_POLL_MS)
      }
      log(
          "warn",
          "tile · $label not sent · bluetooth is $hidLinkWord after " +
              "${TILE_HID_WAIT_MS / 1000} s",
      )
    }
  }

  private val hidLinkWord: String
    get() =
        when (hidLink) {
          HidLinkState.Connected -> "connected"
          HidLinkState.WaitingForHost -> "waiting for the Mac to connect"
          HidLinkState.Unavailable -> "unavailable (not paired, or permission not granted)"
        }

  /**
   * The phone has no speech recognizer.
   *
   * Logged rather than swallowed: a mic button that does nothing when pressed is indistinguishable
   * from one that is broken, and the remedy (install a recognizer, or use the keyboard's own mic)
   * is not one the app can guess at.
   */
  public fun noteNoSpeechRecognizer() {
    log("warn", "dictation · no speech recognizer on this phone")
  }

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
      updateSelected { it.copy(token = "") }
      regeneratePairCode()
      log("warn", "$what · token rejected, pair again with the new code")
      return
    }
    log("warn", "$what · ${failureText(error)}")
  }

  /** An auth failure has a remedy and says so; everything else is the Mac not answering. */
  /**
   * One line a status row can hold. A JSON parse error quotes the whole document it choked on; 64
   * KiB of that as a status label pushed the entire dashboard off the bottom of the screen.
   */
  private fun failureText(error: Throwable): String {
    if (error is AgentAuthException) return "not paired"
    val text = (error.message ?: error::class.simpleName ?: "error").lineSequence().first()
    return if (text.length > FAILURE_TEXT_MAX) text.take(FAILURE_TEXT_MAX) + "…" else text
  }

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

  private fun plural(count: Int): String = if (count == 1) "" else "s"

  private companion object {
    const val POINTER_HINT = "drag · tap · 2-finger scroll · hold to drag · 3-finger swipe"

    const val PAIR_TTL_MS = 5 * 60 * 1000L
    const val PAIR_CODE_BOUND = 1_000_000
    const val CLAUDE_TIMEOUT_S = 180
    const val RECENT_COMMANDS = 20
    const val SLOW_POLL_EVERY = 3

    /** The contract samples PRs every 60 s on the Mac; asking faster only spends rate limit. */
    const val PR_POLL_MS = 60_000L
    const val RUNNING_LABEL_MAX = 40
    const val NOTIFY_BODY_MAX = 80

    /** How long a tile waits for the Bluetooth link before saying why it gave up. */
    const val TILE_HID_WAIT_MS = 5_000L
    const val TILE_HID_POLL_MS = 250L
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
    const val SERIES_ROWS = 12

    /** How many series the Mac screen's panel shows before it stops. */
    const val PANEL_ROWS = 8
    const val FAILURE_TEXT_MAX = 120
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
          // Typed like Restart, for the same reason: a merge lands on a
          // branch other people are working from and no button on this phone
          // can take it back.
          is DialogKind.MergePr ->
              DialogSpec(
                  kicker = "Destructive · pull request",
                  destructive = true,
                  title = "Merge ${kind.repo}#${kind.number}?",
                  body =
                      "${Format.clip(kind.title)}\n\n" +
                          "Runs gh pr merge --merge on the Mac. Branch protection still applies; " +
                          "if GitHub refuses, its reason lands in the event log.",
                  action = "Merge",
                  word = "merge".takeIf { confirmDestructive },
              )
          is DialogKind.SyncApp ->
              DialogSpec(
                  kicker = "Destructive · argocd",
                  destructive = true,
                  title = "Sync ${kind.name}?",
                  body =
                      "Reconciles ${kind.namespace}/${kind.name} to what is in git. " +
                          "Anything changed in the cluster by hand is replaced.",
                  action = "Sync",
                  word = "sync".takeIf { confirmDestructive },
              )
        }
  }
}
